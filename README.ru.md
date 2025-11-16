# angie-ctl

Простой скрипт для управления HTTP-конфигурациями и модулями Angie, аналогичный a2enconf/a2enmod для Apache.
Позволяет включать, отключать и просматривать доступные/включённые конфиги и модули через симлинки.

## Возможности

- Включение/отключение HTTP-конфигов и модулей по имени
- Просмотр доступных и включённых конфигов/модулей
- Автоматическая проверка конфигурации Angie после изменений

## Использование

```
./angie-ctl.sh {httpconf|mod} {en|dis|ls|ls-available|ls-enabled} [name ...]
```

### Примеры

Включить конфиг:

```
./angie-ctl.sh httpconf en drupal
./angie-ctl.sh httpconf en drupal.conf
```

Отключить конфиг:

```
./angie-ctl.sh httpconf dis drupal
```

Включить модуль:

```
./angie-ctl.sh mod en geoip
```

Отключить модуль:

```
./angie-ctl.sh mod dis geoip
```

Посмотреть включённые конфиги/модули:

```
./angie-ctl.sh httpconf ls
./angie-ctl.sh mod ls
```

Посмотреть все доступные конфиги/модули:

```
./angie-ctl.sh httpconf ls-available
./angie-ctl.sh mod ls-available
```

Посмотреть все включённые конфиги/модули:

```
./angie-ctl.sh httpconf ls-enabled
./angie-ctl.sh mod ls-enabled
```

## Директории

- Доступные конфиги: `/etc/angie/http-conf-available.d`
- Включённые конфиги: `/etc/angie/http-conf.d`
- Доступные модули: `/etc/angie/modules-available.d`
- Включённые модули: `/etc/angie/modules.d`

## Требования

- Установленный Angie, доступный через `$ANGIE_BIN` (по умолчанию: `angie`)
- Достаточные права для создания/удаления симлинков в конфиг-директориях Angie

## Примечания

- После включения/отключения скрипт выполняет `angie -t` для проверки конфигурации
- Имена можно указывать с расширением `.conf` или без него
