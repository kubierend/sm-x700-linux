// SPDX-License-Identifier: GPL-2.0-only
/*
 * Debug-only port of Qualcomm's downstream sys_pm_vx ("system PM violators") for the
 * Galaxy Tab S8 (sm8450 / "waipio"), as an out-of-tree module: no DT change needed.
 *
 * On system suspend it asks the AOP (via qcom_aoss qmp_send) to log, once per second,
 * which RPMh DRVs still block CX power collapse. The AOP writes that log to its message
 * RAM at 0x0c320000 (stock DT: sys-pm-vx@c320000). After resume, read
 * /sys/kernel/debug/sys_pm_vx/violators. Writing anything to .../flush sends the
 * downstream "log_once" message so the AOP writes out entries it still holds.
 *
 * Log layout and DRV names follow msm-kernel drivers/soc/qcom/sys_pm_vx.c.
 */
#include <linux/debugfs.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/seq_file.h>
#include <linux/soc/qcom/qcom_aoss.h>

#define VX_BASE		0x0c320000
#define VX_SIZE		0x400

#define MODE_AOSS	0xaa
#define MODE_CXPC	0xcc
#define MODE_DDR	0xdd

static const char * const drv_names_waipio[] = {
	"TZ", "HYP", "HLOS", "L3", "SECPROC", "AUDIO", "SENSOR", "AOP",
	"DEBUG", "GPU", "DISPLAY", "COMPUTE_DSP", "TME_SW", "TME_HW",
	"MDM SW", "MDM HW", "WLAN RF", "WLAN BB", "DDR AUX", "ARC CPRF",
};
#define NDRV ARRAY_SIZE(drv_names_waipio)

static void __iomem *vx_base;
static struct qmp *vx_qmp;
static struct device *vx_aoss_dev;
static struct dentry *vx_dir;
static struct platform_device *vx_pdev;
static bool vx_armed = true;
static unsigned int vx_sent;
static int vx_last_ret;

static int vx_send(bool enable)
{
	int ret;

	if (enable)
		ret = qmp_send(vx_qmp,
			"{class: lpm_mon, type: cxpc, dur: 1000, flush: 10, ts_adj: 1}");
	else
		ret = qmp_send(vx_qmp,
			"{class: lpm_mon, type: cxpc, dur: 1000, flush: 1, log_once: 1}");
	vx_last_ret = ret;
	vx_sent++;
	return ret;
}

static const char *mode_str(u8 m)
{
	return m == MODE_CXPC ? "CXPC" : m == MODE_AOSS ? "AOSS" :
	       m == MODE_DDR ? "DDR" : "?";
}

static int vx_violators_show(struct seq_file *s, void *unused)
{
	u32 itr = 0, val, ts;
	u8 type, logsize, ts_shift, flush;
	u16 dur;
	int i, j, k;
	bool entered = false;

	val = readl(vx_base + itr); itr += 4;
	type = val & 0xff;
	logsize = (val >> 8) & 0xff;
	seq_printf(s, "word0=%#010x", val);
	val = readl(vx_base + itr); itr += 4;
	dur = val & 0xffff;
	ts_shift = (val >> 16) & 0xff;
	flush = (val >> 24) & 0xff;
	seq_printf(s, " word1=%#010x\nmode=%s dur_ms=%u ts_shift=%u flush=%u logsize=%u\n",
		   val, mode_str(type), dur, ts_shift, flush, logsize);
	seq_printf(s, "armed=%d messages_sent=%u last_qmp_ret=%d\n",
		   vx_armed, vx_sent, vx_last_ret);
	if (!logsize || logsize > (VX_SIZE - 8) / (4 + ALIGN(NDRV, 4)))
		return 0;

	for (i = 0; i < logsize; i++) {
		u32 vx[ALIGN(NDRV, 4)];
		u32 any = 0;

		ts = readl(vx_base + itr); itr += 4;
		if (!ts)
			break;
		for (j = 0; j < NDRV;) {
			val = readl(vx_base + itr); itr += 4;
			for (k = 0; k < 4; k++)
				vx[j++] = (val >> (8 * k)) & 0xff;
		}
		seq_printf(s, "%10x |", ts << ts_shift);
		for (j = 0; j < NDRV; j++)
			any |= vx[j];
		if (!any) {
			/* An all-zero line marks entry into / exit from the low-power mode. */
			seq_printf(s, " %s %s\n", mode_str(type), entered ? "Exit" : "Enter");
			entered = !entered;
			continue;
		}
		for (j = 0; j < NDRV; j++)
			if (vx[j])
				seq_printf(s, " %s(%u)", drv_names_waipio[j], vx[j]);
		seq_puts(s, "\n");
	}
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(vx_violators);

static int vx_raw_show(struct seq_file *s, void *unused)
{
	int i;

	for (i = 0; i < VX_SIZE; i += 16)
		seq_printf(s, "%03x: %08x %08x %08x %08x\n", i,
			   readl(vx_base + i), readl(vx_base + i + 4),
			   readl(vx_base + i + 8), readl(vx_base + i + 12));
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(vx_raw);

static ssize_t vx_cmd_write(struct file *f, const char __user *ubuf, size_t len,
			    loff_t *off)
{
	char buf[8] = {};
	int ret;

	if (copy_from_user(buf, ubuf, min(len, sizeof(buf) - 1)))
		return -EFAULT;
	if (!strncmp(buf, "on", 2))
		ret = vx_send(true);
	else if (!strncmp(buf, "off", 3))
		ret = vx_send(false);
	else if (!strncmp(buf, "arm", 3))
		ret = (vx_armed = true, 0);
	else if (!strncmp(buf, "disarm", 6))
		ret = (vx_armed = false, 0);
	else
		return -EINVAL;
	return ret ? ret : len;
}

static const struct file_operations vx_cmd_fops = {
	.write = vx_cmd_write,
};

static int vx_suspend(struct device *dev)
{
	if (vx_armed)
		vx_send(true);
	return 0;
}

static DEFINE_SIMPLE_DEV_PM_OPS(vx_pm_ops, vx_suspend, NULL);

static struct platform_driver vx_driver = {
	.driver = {
		.name = "sys_pm_vx_probe",
		.pm = pm_sleep_ptr(&vx_pm_ops),
	},
};

static int __init vx_init(void)
{
	struct platform_device *aoss;
	struct device_node *np;
	int ret;

	np = of_find_compatible_node(NULL, NULL, "qcom,aoss-qmp");
	if (!np)
		return -ENODEV;
	aoss = of_find_device_by_node(np);
	of_node_put(np);
	if (!aoss)
		return -ENODEV;
	vx_qmp = platform_get_drvdata(aoss);
	if (!vx_qmp) {
		put_device(&aoss->dev);
		return -EPROBE_DEFER;
	}
	vx_aoss_dev = &aoss->dev;

	vx_base = ioremap(VX_BASE, VX_SIZE);
	if (!vx_base) {
		ret = -ENOMEM;
		goto put;
	}

	ret = platform_driver_register(&vx_driver);
	if (ret)
		goto unmap;
	vx_pdev = platform_device_register_simple("sys_pm_vx_probe", -1, NULL, 0);
	if (IS_ERR(vx_pdev)) {
		ret = PTR_ERR(vx_pdev);
		goto unreg;
	}

	vx_dir = debugfs_create_dir("sys_pm_vx", NULL);
	debugfs_create_file("violators", 0400, vx_dir, NULL, &vx_violators_fops);
	debugfs_create_file("raw", 0400, vx_dir, NULL, &vx_raw_fops);
	debugfs_create_file("cmd", 0200, vx_dir, NULL, &vx_cmd_fops);
	return 0;

unreg:
	platform_driver_unregister(&vx_driver);
unmap:
	iounmap(vx_base);
put:
	put_device(vx_aoss_dev);
	return ret;
}

static void __exit vx_exit(void)
{
	debugfs_remove_recursive(vx_dir);
	platform_device_unregister(vx_pdev);
	platform_driver_unregister(&vx_driver);
	iounmap(vx_base);
	put_device(vx_aoss_dev);
}

module_init(vx_init);
module_exit(vx_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("sm8450 AOP CX-collapse violator log (debug port of downstream sys_pm_vx)");
