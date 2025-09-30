# Moodle Migration Manager - Menú Interactivo

## Descripción

El **Moodle Migration Manager** es un menú interactivo que facilita la migración de Moodle de versiones antiguas a 4.5 LTS de manera segura y controlada.

## Características

- **Análisis automático** de backups de Moodle
- **Detección de versión** actual y recomendación de migración
- **Configuración interactiva** de rutas y parámetros
- **Migración progresiva** con actualización de PHP (3.10→3.11→4.1→4.4→4.5 LTS)
- **Monitoreo en tiempo real** del estado de servicios
- **Logs detallados** de todas las operaciones
- **Limpieza automática** del entorno

## Archivos del Sistema

```
/root/docker/moodle_staging/
├── moodle_migration_manager.sh    # Menú interactivo principal
├── migrate_moodle.sh              # Script de migración automática
├── migration_config.conf          # Configuración (generado automáticamente)
├── migration.log                  # Logs de migración (generado automáticamente)
├── README_MENU.md                 # Esta documentación
├── README_MIGRATION.md            # Documentación técnica completa
└── QUICK_START.md                 # Guía de inicio rápido
```

## Uso

### 1. Ejecutar el Manager

```bash
cd /root/docker/moodle_staging
sudo ./moodle_migration_manager.sh
```

### 2. Menú Principal

```
==================================================
    MOODLE MIGRATION MANAGER - MENÚ INTERACTIVO
==================================================

=== MENÚ PRINCIPAL ===
1. Analizar backup de Moodle
2. Configurar rutas de archivos
3. Ejecutar migración automática
4. Ver estado actual
5. Ver logs de migración
6. Limpiar entorno
7. Ayuda
8. Salir
```

### 3. Flujo Recomendado

#### Paso 1: Analizar Backup
- Selecciona opción **1**
- Ingresa la ruta del backup de Moodle (.tar.gz)
- El sistema analizará automáticamente:
  - Versión actual de Moodle
  - Configuración de base de datos
  - Estructura de archivos
  - Recomendación de migración

#### Paso 2: Configurar Rutas
- Selecciona opción **2**
- Configura las rutas de:
  - Backup de Moodle (.tar.gz)
  - Dump de base de datos (.sql)

#### Paso 3: Ejecutar Migración
- Selecciona opción **3**
- El sistema ejecutará automáticamente:
  - Migración 3.10 → 3.11 (PHP 7.4)
  - Migración 3.11 → 4.1 LTS (PHP 8.0)
  - Migración 4.1 → 4.4 LTS (PHP 8.2)
  - Migración 4.4 → 4.5 LTS (PHP 8.2)

#### Paso 4: Verificar Estado
- Selecciona opción **4**
- Verifica que todo esté funcionando correctamente

## Funciones del Menú

### 1. Analizar backup de Moodle
- **Función:** Analiza automáticamente el backup de Moodle
- **Detecta:** Versión actual, configuración de DB, estructura
- **Genera:** Recomendación de migración
- **Archivos:** Extrae temporalmente el backup para análisis

### 2. Configurar rutas de archivos
- **Función:** Configura las rutas de los archivos necesarios
- **Archivos:** Backup de Moodle (.tar.gz) y dump de DB (.sql)
- **Validación:** Verifica que los archivos existan
- **Persistencia:** Guarda la configuración para uso posterior

### 3. Ejecutar migración automática
- **Función:** Ejecuta la migración completa automáticamente
- **Proceso:** Migración progresiva con actualización de PHP
- **Backups:** Crea backups automáticos antes de cada upgrade
- **Logs:** Registra todo el proceso en migration.log

### 4. Ver estado actual
- **Función:** Muestra el estado actual del sistema
- **Información:** Versión detectada, servicios Docker, configuración
- **Monitoreo:** Estado de contenedores y servicios

### 5. Ver logs de migración
- **Función:** Muestra los logs de migración y servicios
- **Logs:** migration.log, logs de Docker, logs de servicios
- **Útil para:** Troubleshooting y monitoreo

### 6. Limpiar entorno
- **Función:** Limpia completamente el entorno
- **Acciones:** Detiene servicios, elimina contenedores, limpia volúmenes
- **Advertencia:** Operación destructiva, requiere confirmación

### 7. Ayuda
- **Función:** Muestra información de ayuda
- **Contenido:** Descripción, flujo recomendado, requisitos, comandos útiles

### 8. Salir
- **Función:** Sale del programa
- **Acción:** Termina la ejecución del menú

## Ejemplo de Uso Completo

```bash
# 1. Ejecutar el manager
sudo ./moodle_migration_manager.sh

# 2. Analizar backup (opción 1)
# Ingresa: /path/to/moodle_backup_20250926_230701.tar.gz
# Resultado: Versión detectada: 3.10+ (Build: 20201224)

# 3. Configurar rutas (opción 2)
# Backup Moodle: /path/to/moodle_backup_20250926_230701.tar.gz
# Dump DB: /path/to/bitnami_moodle_3_10_dump.sql

# 4. Ejecutar migración (opción 3)
# El sistema ejecutará automáticamente la migración completa

# 5. Verificar estado (opción 4)
# Resultado: Moodle 4.5 LTS ejecutándose
```

## Requisitos

- **Sistema:** Linux (Ubuntu/Debian recomendado)
- **Permisos:** Ejecutar como root
- **Software:** Docker, Docker Compose
- **Archivos:** Backup de Moodle (.tar.gz), dump de DB (.sql)
- **Espacio:** Mínimo 5GB libres
- **Red:** Puerto 8200 y 3307 disponibles

## Troubleshooting

### Error: "Docker no está instalado"
```bash
# Instalar Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
```

### Error: "Archivo de backup no existe"
- Verificar que la ruta sea correcta
- Verificar que el archivo exista
- Verificar permisos de lectura

### Error: "Puerto ya en uso"
- Cambiar puertos en la configuración
- Detener servicios que usen esos puertos
- Usar opción 6 para limpiar entorno

### Error: "No se pudo determinar la versión"
- Verificar que el backup contenga el directorio moodle
- Verificar que exista el archivo version.php
- Verificar que el backup no esté corrupto

## Logs y Monitoreo

### Archivos de Log
- **migration.log:** Log completo de la migración
- **Docker logs:** Logs de contenedores
- **Apache logs:** Logs del servicio web

### Comandos de Monitoreo
```bash
# Ver logs de migración
tail -f migration.log

# Ver logs de Docker
docker logs -f moodle_staging_web
docker logs -f moodle_staging_mariadb

# Ver estado de servicios
docker ps | grep moodle_staging
```

## Seguridad

- **Backups automáticos:** Se crean antes de cada upgrade
- **Validación de archivos:** Verifica existencia y permisos
- **Confirmaciones:** Requiere confirmación para operaciones destructivas
- **Logs detallados:** Registra todas las operaciones
- **Rollback:** Posibilidad de restaurar desde backups

## Soporte

Si encuentras problemas:

1. **Revisar logs:** Opción 5 del menú
2. **Verificar estado:** Opción 4 del menú
3. **Limpiar entorno:** Opción 6 del menú
4. **Consultar documentación:** README_MIGRATION.md
5. **Verificar requisitos:** Ayuda (opción 7)

## Notas Importantes

- **Backups:** Siempre se crean automáticamente antes de cada upgrade
- **Tiempo:** La migración completa puede tomar 30-60 minutos
- **Espacio:** Asegúrate de tener suficiente espacio libre
- **Red:** El sistema crea una red Docker llamada `moodle_net`
- **Permisos:** Debe ejecutarse como root para acceder a Docker
- **Versiones:** Soporta migración desde Moodle 3.10 hasta 4.5 LTS
