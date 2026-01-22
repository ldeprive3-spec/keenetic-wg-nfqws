# Одна команда установки:
curl -fsSL https://raw.githubusercontent.com/ldeprive3-spec/keenetic-wg-nfqws/main/install.sh | sh

# Проверка:
ps | grep nfqws
tail -f /opt/var/log/nfqws.log
tail -f /opt/var/log/wg-restore.log

Ключевые отличия от v2.3:
| Параметр          | v2.3             | v2.5                        |
| ----------------- | ---------------- | --------------------------- |
| Netfilter check   | ❌ nf_queue       | ✅ nfnetlink_queue via /proc |
| WireGuard check   | ❌ modprobe/lsmod | ✅ /proc/modules             |
| NFQWS конфиг      | ❌ Параметры      | ✅ Shell переменные          |
| opkg update       | ❌ Нет            | ✅ Да                        |
| nano/nfqws-web    | ❌ Нет            | ✅ Установлены               |
| WireGuard restore | ❌ Нет            | ✅ Ground-Zerro daemon       |
| KeenOS поддержка  | 5.0+             | 4.x и 5.x                   |
| NFQWS конфиг      | Полный           | WARP-only (чистый)          |
