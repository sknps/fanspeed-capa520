#!/bin/bash

# Проверка на запуск от root
if [ "$EUID" -ne 0 ]; then 
  echo "Пожалуйста, запустите скрипт с sudo"
  exit
fi

echo "--- Настройка охлаждения Axiomtek CAPA520 (Универсальная версия) ---"

# 1. Установка утилит
echo "[1/6] Установка lm-sensors и fancontrol..."
apt update && apt install -y lm-sensors fancontrol

# 2. Настройка GRUB
echo "[2/6] Настройка GRUB (acpi_enforce_resources=lax)..."
if ! grep -q "acpi_enforce_resources=lax" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="acpi_enforce_resources=lax /' /etc/default/grub
    update-grub
    echo "!!! Параметры ядра изменены. Потребуется ПЕРЕЗАГРУЗКА."
else
    echo "Параметры ядра уже настроены."
fi

# 3. Активация драйвера Fintek
echo "[3/6] Настройка модуля f71882fg..."
modprobe f71882fg
if ! grep -q "f71882fg" /etc/modules; then
    echo "f71882fg" >> /etc/modules
fi

# 4. Создание базового шаблона конфига
# Используем метки hwmon1 и hwmon2, которые скрипт запуска заменит на реальные
echo "[4/6] Создание шаблона /etc/fancontrol..."
cat <<EOT > /etc/fancontrol
INTERVAL=10
FCTEMPS=hwmon2/device/pwm1=hwmon1/temp1_input
FCFANS=hwmon2/device/pwm1=hwmon2/device/fan1_input
MINTEMP=hwmon2/device/pwm1=40
MAXTEMP=hwmon2/device/pwm1=75
MINSTART=hwmon2/device/pwm1=80
MINSTOP=hwmon2/device/pwm1=60
MINPWM=hwmon2/device/pwm1=60
MAXPWM=hwmon2/device/pwm1=255
EOT

# 5. Создание скрипта автоматического определения путей
echo "[5/6] Создание скрипта динамического запуска..."
cat <<'EOT' > /usr/local/bin/fancontrol-smart-start.sh
#!/bin/bash
# Поиск реальных путей
H_CPU=$(basename $(ls -d /sys/class/hwmon/hwmon* | while read d; do [ -f "$d/name" ] && grep -q "coretemp" "$d/name" && echo $d; done | head -n 1))
H_FANS=$(basename $(ls -d /sys/class/hwmon/hwmon* | while read d; do [ -f "$d/name" ] && grep -qE "f81768d|f71882fg|f71869|f81865f" "$d/name" && echo $d; done | head -n 1))

if [ -z "$H_CPU" ] || [ -z "$H_FANS" ]; then
    echo "Ошибка: Устройства охлаждения не найдены!"
    exit 1
fi

# Подмена меток в конфиге и запуск
sed "s/hwmon1/$H_CPU/g; s/hwmon2/$H_FANS/g" /etc/fancontrol > /tmp/fancontrol.actual
exec /usr/sbin/fancontrol /tmp/fancontrol.actual
EOT

chmod +x /usr/local/bin/fancontrol-smart-start.sh

# 6. Настройка службы systemd (через override)
echo "[6/6] Настройка службы fancontrol..."
mkdir -p /etc/systemd/system/fancontrol.service.d
cat <<EOT > /etc/systemd/system/fancontrol.service.d/override.conf
[Service]
ExecStartPre=
ExecStart=
ExecStart=/usr/local/bin/fancontrol-smart-start.sh
EOT

systemctl daemon-reload
systemctl enable fancontrol
# Не перезапускаем сразу, так как может потребоваться перезагрузка после GRUB
echo "--- Настройка завершена! ---"
echo "Рекомендуется перезагрузить систему для применения параметров ACPI."
