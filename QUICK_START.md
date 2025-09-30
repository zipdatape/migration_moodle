# Guía de Inicio Rápido - Migración Moodle

## Uso del Script Automático

### 1. Preparación

```bash
# Descargar el script
cd /root/docker
git clone <tu-repositorio> moodle_staging
cd moodle_staging

# Hacer ejecutable
chmod +x migrate_moodle.sh
```

### 2. Ejecución

```bash
# Ejecutar como root
sudo ./migrate_moodle.sh
```

### 3. Configuración Interactiva

El script te pedirá:

- **IP local:** `localhost` (por defecto)
- **Puerto web:** `8200` (por defecto)
- **Puerto DB:** `3307` (por defecto)
- **Directorio base:** `/root/docker/moodle_staging` (por defecto)
- **Backup Moodle:** Ruta completa al archivo `.tar.gz`
- **Dump DB:** Ruta completa al archivo `.sql`
- **Base de datos:** `desa_dbcunix_desacapaolacefs` (por defecto)
- **Prefijo tablas:** `mco_` (por defecto)
- **Usuario admin:** `sosadmin` (por defecto)
- **Contraseña admin:** `Admin123!` (por defecto)

### 4. Ejemplo de Uso

```bash
# Ejemplo con archivos específicos
./migrate_moodle.sh

# El script preguntará:
# IP local: localhost
# Puerto web: 8200
# Puerto DB: 3307
# Directorio base: /root/docker/moodle_staging
# Backup Moodle: /path/to/moodle_backup_20250926_230701.tar.gz
# Dump DB: /path/to/bitnami_moodle_3_10_dump.sql
# Base de datos: desa_dbcunix_desacapaolacefs
# Prefijo tablas: mco_
# Usuario admin: sosadmin
# Contraseña admin: Admin123!
```

### 5. Resultado

Al finalizar, tendrás:

- **Moodle 4.4.10+ LTS** ejecutándose
- **PHP 8.2.29** (seguro hasta 2026)
- **Acceso web:** http://localhost:8200
- **Login:** `sosadmin` / `Admin123!`

## Comandos Post-Migración

```bash
# Ver logs
docker logs moodle_staging_web
docker logs moodle_staging_mariadb

# Acceder a contenedores
docker exec -it moodle_staging_web bash
docker exec -it moodle_staging_mariadb bash

# Reiniciar servicios
cd /root/docker/moodle_staging/services
docker-compose -f docker-compose.db.yml restart
cd web && docker-compose restart

# Parar servicios
cd /root/docker/moodle_staging/services
docker-compose -f docker-compose.db.yml down
cd web && docker-compose down
```

## Validación

1. **Acceso:** http://localhost:8200
2. **Login:** `sosadmin` / `Admin123!`
3. **Verificar versión:** Pie de página debe mostrar "4.4.10+"
4. **Verificar PHP:** Administración del sitio > Servidor > Entorno
5. **Verificar cron:** Administración del sitio > Servidor > Tareas programadas

## Troubleshooting

### Error: "Docker no está instalado"
```bash
# Instalar Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
```

### Error: "Docker Compose no está instalado"
```bash
# Instalar Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### Error: "Archivo de backup no existe"
Verificar que las rutas a los archivos de backup sean correctas y que los archivos existan.

### Error: "Puerto ya en uso"
Cambiar los puertos en la configuración interactiva o detener servicios que usen esos puertos.

## Notas Importantes

1. **Backups:** El script crea backups automáticamente antes de cada upgrade
2. **Tiempo:** La migración completa puede tomar 30-60 minutos
3. **Espacio:** Asegúrate de tener al menos 5GB de espacio libre
4. **Red:** El script crea una red Docker llamada `moodle_net`
5. **Permisos:** Debe ejecutarse como root para acceder a Docker

## Soporte

Si encuentras problemas:

1. Revisar los logs: `docker logs moodle_staging_web`
2. Verificar la documentación completa: `README_MIGRATION.md`
3. Comprobar que todos los archivos de backup existan
4. Verificar que Docker y Docker Compose estén instalados
