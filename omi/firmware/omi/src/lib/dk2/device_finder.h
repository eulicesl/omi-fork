#ifndef DEVICE_FINDER_H
#define DEVICE_FINDER_H

#include <zephyr/kernel.h>

/**
 * @brief Registers the Device Finder BLE service.
 */
void register_device_finder_service(void);

/**
 * @brief Starts the device-finder sequence.
 */
void device_finder_start(void);

/**
 * @brief Stops the device-finder sequence.
 */
void device_finder_stop(void);

#endif /* DEVICE_FINDER_H */
