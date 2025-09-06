#include <zephyr/kernel.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/logging/log.h>
#include "lib/dk2/device_finder.h"
#include "lib/dk2/led.h"
#include "lib/dk2/haptic.h"

LOG_MODULE_REGISTER(device_finder, CONFIG_LOG_DEFAULT_LEVEL);

static bool device_finder_active;
static struct k_work_delayable device_finder_work;

/* UUID definitions */
static struct bt_uuid_128 df_service_uuid = BT_UUID_INIT_128(
    BT_UUID_128_ENCODE(0x19B10030, 0xE8F2, 0x537E, 0x4F6C, 0xD104768A1214));

static struct bt_uuid_128 df_char_uuid = BT_UUID_INIT_128(
    BT_UUID_128_ENCODE(0x19B10031, 0xE8F2, 0x537E, 0x4F6C, 0xD104768A1214));

static ssize_t df_write_handler(struct bt_conn *conn, const struct bt_gatt_attr *attr,
                                const void *buf, uint16_t len, uint16_t offset, uint8_t flags)
{
    if (len < 1) {
        return BT_GATT_ERR(BT_ATT_ERR_INVALID_ATTRIBUTE_LEN);
    }
    uint8_t value = ((const uint8_t *)buf)[0];
    if (value) {
        device_finder_start();
    } else {
        device_finder_stop();
    }
    return len;
}

static struct bt_gatt_attr df_attrs[] = {
    BT_GATT_PRIMARY_SERVICE(&df_service_uuid),
    BT_GATT_CHARACTERISTIC(&df_char_uuid.uuid, BT_GATT_CHRC_WRITE,
                           BT_GATT_PERM_WRITE, NULL, df_write_handler, NULL),
};

static struct bt_gatt_service df_service = BT_GATT_SERVICE(df_attrs);

static void device_finder_work_handler(struct k_work *work)
{
    static bool state = false;

    if (!device_finder_active) {
        set_led_red(false);
        set_led_green(false);
        set_led_blue(false);
        haptic_off();
        return;
    }

    if (state) {
        set_led_red(false);
        set_led_green(false);
        set_led_blue(false);
        haptic_off();
    } else {
        set_led_red(true);
        set_led_green(true);
        set_led_blue(true);
        play_haptic_milli(200);
    }

    state = !state;
    k_work_schedule(&device_finder_work, K_MSEC(500));
}

void device_finder_start(void)
{
    if (device_finder_active) {
        return;
    }
    device_finder_active = true;
    k_work_init_delayable(&device_finder_work, device_finder_work_handler);
    k_work_schedule(&device_finder_work, K_NO_WAIT);
    LOG_INF("Device Finder started");
}

void device_finder_stop(void)
{
    if (!device_finder_active) {
        return;
    }
    device_finder_active = false;
    k_work_cancel_delayable(&device_finder_work);
    set_led_red(false);
    set_led_green(false);
    set_led_blue(false);
    haptic_off();
    LOG_INF("Device Finder stopped");
}

void register_device_finder_service(void)
{
    int err = bt_gatt_service_register(&df_service);
    if (err) {
        LOG_ERR("Device Finder service registration failed (err %d)", err);
    } else {
        LOG_INF("Device Finder service registered");
    }
}
