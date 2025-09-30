# Migración Moodle 3.10 → 4.4 LTS

## Resumen del Proceso

Esta documentación describe la migración exitosa de Moodle 3.10 a 4.4 LTS con actualización de PHP de 7.4 a 8.2, realizada en un entorno Docker.

## Arquitectura Final

- **Moodle 4.4.10+ LTS** (Build: 20250926)
- **PHP 8.2.29** (soporte hasta diciembre 2026)
- **MariaDB 10.6** (con parámetros optimizados)
- **Docker Compose** (servicios web y base de datos)

## Estructura de Directorios

```
/root/docker/moodle_staging/
├── services/
│   ├── docker-compose.db.yml    # Servicio MariaDB
│   └── web/
│       ├── Dockerfile           # Imagen PHP 8.2 + Apache
│       └── docker-compose.yml   # Servicio web
├── db_init/
│   └── 01_dump.sql             # Dump SQL original
├── db_splits/
│   ├── preambulo.sql           # Variables de sesión
│   ├── header.sql              # Header del dump
│   └── part_*.sql              # Partes del dump dividido
├── html/
│   ├── moodle/                 # Código fuente Moodle
│   └── moodledata/             # Datos de Moodle
├── backups/                    # Backups antes de cada upgrade
└── README_MIGRATION.md         # Esta documentación
```

## Pasos de Migración Realizados

### 1. Preparación del Entorno

**Nota importante:** El script realiza una migración progresiva actualizando PHP en cada etapa:
- **Moodle 3.10** → **3.11** (PHP 7.4)
- **Moodle 3.11** → **4.1 LTS** (PHP 8.0) 
- **Moodle 4.1** → **4.4 LTS** (PHP 8.2)

#### 1.1 Creación de la Estructura Docker

**Servicio MariaDB** (`services/docker-compose.db.yml`):
```yaml
version: "3.9"
services:
  mariadb:
    image: mariadb:10.6
    container_name: moodle_staging_mariadb
    environment:
      - MARIADB_ROOT_PASSWORD=
      - MARIADB_DATABASE=desa_dbcunix_desacapaolacefs
      - MARIADB_USER=bn_moodle
      - MARIADB_PASSWORD=
    command: [
      "--character-set-server=utf8mb4",
      "--collation-server=utf8mb4_unicode_ci",
      "--innodb_buffer_pool_size=256M",
      "--max_allowed_packet=512M",
      "--innodb_log_file_size=512M",
      "--innodb_flush_log_at_trx_commit=2",
      "--tmp_table_size=256M",
      "--max_heap_table_size=256M"
    ]
    volumes:
      - mariadb_data:/var/lib/mysql
      - ../db_init:/docker-entrypoint-initdb.d:ro
    networks:
      - moodle_net
    ports:
      - "3307:3306"

volumes:
  mariadb_data:

networks:
  moodle_net:
    driver: bridge
```

**Dockerfile PHP 7.4** (`services/web/Dockerfile` - versión inicial):
```dockerfile
FROM php:7.4-apache

RUN apt-get update && apt-get install -y \
    libpng-dev libjpeg-dev libfreetype6-dev \
    libzip-dev zip \
    libicu-dev \
    libxml2-dev \
    libldap2-dev \
    libxslt1.1 libxslt1-dev \
    ghostscript \
    cron \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd intl zip mysqli soap xsl opcache

RUN a2enmod rewrite headers expires && \
    sed -i 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf

WORKDIR /var/www/html
```

**Servicio Web** (`services/web/docker-compose.yml`):
```yaml
version: "3.9"
services:
  web:
    build: .
    container_name: moodle_staging_web
    volumes:
      - ../../html:/var/www/html
      - ../../moodledata:/var/www/moodledata
    networks:
      - moodle_net
    ports:
      - "8200:80"
    depends_on:
      - mariadb

networks:
  moodle_net:
    external: true
```

#### 1.2 Configuración de Moodle (`html/moodle/config.php`)

```php
<?php
unset($CFG);
global $CFG;
$CFG = new stdClass();

$CFG->dbtype    = 'mariadb';
$CFG->dblibrary = 'native';
$CFG->dbhost    = 'mariadb';
$CFG->dbname    = 'desa_dbcunix_desacapaolacefs';
$CFG->dbuser    = 'root';
$CFG->dbpass    = '';
$CFG->prefix    = 'mco_';
$CFG->dboptions = array(
    'dbpersist' => 0,
    'dbport' => 3306,
    'dbsocket' => '',
    'dbcollation' => 'utf8mb4_unicode_ci',
);

$CFG->wwwroot   = 'http://localhost:8200';
$CFG->dataroot  = '/var/www/moodledata';
$CFG->admin     = 'admin';
$CFG->directorypermissions = 0777;
$CFG->sslproxy = false;
$CFG->theme = 'boost';

require_once(__DIR__ . '/lib/setup.php');
```

### 2. Importación de Base de Datos

#### 2.1 División del Dump SQL

Para manejar dumps grandes, se dividió el archivo SQL:

```bash
# Crear preámbulo con variables de sesión
cat > db_splits/preambulo.sql << 'EOF'
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS;
SET FOREIGN_KEY_CHECKS=0;
SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS;
SET UNIQUE_CHECKS=0;
SET @OLD_TIME_ZONE=@@TIME_ZONE;
SET TIME_ZONE='+00:00';
SET @saved_cs_client=@@character_set_client;
SET character_set_client = utf8mb4;
EOF

# Dividir dump en partes manejables
csplit -f part_ -b '%03d.sql' 01_dump.sql '/^-- Table structure for table/' '{*}'

# Importar concatenando preámbulo + header + partes
cat db_splits/preambulo.sql db_splits/header.sql db_splits/part_*.sql | \
docker exec -i moodle_staging_mariadb bash -lc \
"mysql -uroot --password= --default-character-set=utf8mb4 --max_allowed_packet=1073741824 desa_dbcunix_desacapaolacefs"
```

### 3. Migración de Versiones

#### 3.1 Moodle 3.10 → 3.11

**Descarga:**
```bash
curl -L -o moodle-3.11.tgz https://github.com/moodle/moodle/archive/refs/heads/MOODLE_311_STABLE.tar.gz
```

**Proceso:**
1. Backup de base de datos y moodledata
2. Descarga de Moodle 3.11
3. Reemplazo del core conservando `config.php`
4. Resolución de dependencias de plugins obsoletos
5. Upgrade CLI

**Comandos:**
```bash
# Backup
docker exec moodle_staging_mariadb bash -lc "mysqldump -uroot --password= --single-transaction --routines --events --triggers desa_dbcunix_desacapaolacefs" > backups/moodle_3_10_before_upgrade.sql
tar -czf backups/moodledata_3_10_before_upgrade.tar.gz -C html moodledata

# Upgrade
tar -xzf moodle-3.11.tgz
mv moodle-MOODLE_311_STABLE moodle-3.11
cp html/moodle/config.php moodle-3.11/
rm -rf html/moodle
mv moodle-3.11 html/moodle
chown -R 33:33 html/moodle

# Resolver dependencias de plugins obsoletos
docker exec moodle_staging_web bash -lc "php admin/cli/upgrade.php --non-interactive"
```

#### 3.2 Moodle 3.11 → 4.1 LTS (PHP 8.0)

**Descarga:**
```bash
curl -L -o moodle-4.1.tgz https://github.com/moodle/moodle/archive/refs/heads/MOODLE_401_STABLE.tar.gz
```

**Actualización de PHP:**
```dockerfile
FROM php:8.0-apache  # Cambio de 7.4 a 8.0
```

**Comando de actualización:**
```bash
sed -i 's/php:7.4-apache/php:8.0-apache/g' services/web/Dockerfile
```

**Proceso:**
1. Backup
2. Actualización del contenedor a PHP 8.0
3. Descarga de Moodle 4.1 LTS
4. Reemplazo del core
5. Configuración de `max_input_vars=5000`
6. Upgrade CLI

**Comandos:**
```bash
# Backup
docker exec moodle_staging_mariadb bash -lc "mysqldump -uroot --password= --single-transaction --routines --events --triggers desa_dbcunix_desacapaolacefs" > backups/moodle_3_11_before_upgrade.sql
tar -czf backups/moodledata_3_11_before_upgrade.tar.gz -C html moodledata

# Actualizar PHP
sed -i 's/php:7.4-apache/php:8.0-apache/g' services/web/Dockerfile
docker compose -f services/web/docker-compose.yml build --no-cache
docker compose -f services/web/docker-compose.yml up -d

# Upgrade a 4.1
tar -xzf moodle-4.1.tgz
mv moodle-MOODLE_401_STABLE moodle-4.1
cp html/moodle/config.php moodle-4.1/
rm -rf html/moodle
mv moodle-4.1 html/moodle
chown -R 33:33 html/moodle

# Configurar PHP y upgrade
docker exec moodle_staging_web bash -c "printf '%s\n' 'max_input_vars=5000' > /usr/local/etc/php/conf.d/moodle.ini && apachectl -k restart"
docker exec moodle_staging_web bash -c "cd /var/www/html && php admin/cli/upgrade.php --non-interactive"
```

#### 3.3 Moodle 4.1 → 4.4 LTS (PHP 8.2)

**Descarga:**
```bash
curl -L -o moodle-4.4.tgz https://github.com/moodle/moodle/archive/refs/heads/MOODLE_404_STABLE.tar.gz
```

**Actualización de PHP:**
```dockerfile
FROM php:8.2-apache  # Cambio de 8.0 a 8.2
```

**Comando de actualización:**
```bash
sed -i 's/php:8.0-apache/php:8.2-apache/g' services/web/Dockerfile
```

**Proceso:**
1. Backup
2. Actualización del contenedor a PHP 8.2
3. Descarga de Moodle 4.4 LTS
4. Reemplazo del core
5. Upgrade CLI

**Comandos:**
```bash
# Backup
docker exec moodle_staging_mariadb bash -lc "mysqldump -uroot --password= --single-transaction --routines --events --triggers desa_dbcunix_desacapaolacefs" > backups/moodle_4_1_before_upgrade.sql
tar -czf backups/moodledata_4_1_before_upgrade.tar.gz -C html moodledata

# Actualizar PHP
sed -i 's/php:8.0-apache/php:8.2-apache/g' services/web/Dockerfile
docker compose -f services/web/docker-compose.yml build --no-cache
docker compose -f services/web/docker-compose.yml up -d

# Upgrade a 4.4
curl -L -o moodle-4.4.tgz https://github.com/moodle/moodle/archive/refs/heads/MOODLE_404_STABLE.tar.gz
tar -xzf moodle-4.4.tgz
mv moodle-MOODLE_404_STABLE moodle-4.4
cp html/moodle/config.php moodle-4.4/
rm -rf html/moodle
mv moodle-4.4 html/moodle
chown -R 33:33 html/moodle

# Configurar PHP y upgrade
docker exec moodle_staging_web bash -c "printf '%s\n' 'max_input_vars=5000' > /usr/local/etc/php/conf.d/moodle.ini && apachectl -k restart"
docker exec moodle_staging_web bash -c "cd /var/www/html && php admin/cli/upgrade.php --non-interactive"
```

### 4. Configuración Post-Migración

#### 4.1 Reset de Contraseña de Administrador

```bash
# Buscar usuario admin
docker exec moodle_staging_mariadb bash -lc "mysql -uroot --password= -D desa_dbcunix_desacapaolacefs -e 'SELECT id,username,auth,suspended,confirmed,email FROM mco_user WHERE deleted=0 AND suspended=0 ORDER BY id LIMIT 5;'"

# Resetear contraseña
docker exec moodle_staging_web bash -lc "php admin/cli/reset_password.php --username=sosadmin --password=Admin123!"
```

#### 4.2 Configuración Final

```bash
# Desactivar mantenimiento
docker exec moodle_staging_web bash -c "cd /var/www/html && php admin/cli/maintenance.php --disable"

# Purgar cachés
docker exec moodle_staging_web bash -c "cd /var/www/html && php admin/cli/purge_caches.php"

# Ejecutar cron
docker exec moodle_staging_web bash -c "cd /var/www/html && php admin/cli/cron.php --keep-alive=1"
```

## URLs de Descarga

- **Moodle 3.11:** https://github.com/moodle/moodle/archive/refs/heads/MOODLE_311_STABLE.tar.gz
- **Moodle 4.1 LTS:** https://github.com/moodle/moodle/archive/refs/heads/MOODLE_401_STABLE.tar.gz
- **Moodle 4.4 LTS:** https://github.com/moodle/moodle/archive/refs/heads/MOODLE_404_STABLE.tar.gz

## Comandos Docker Útiles

```bash
# Ver logs
docker logs moodle_staging_web
docker logs moodle_staging_mariadb

# Acceder al contenedor
docker exec -it moodle_staging_web bash
docker exec -it moodle_staging_mariadb bash

# Reiniciar servicios
docker compose -f services/web/docker-compose.yml restart
docker compose -f services/docker-compose.db.yml restart

# Parar servicios
docker compose -f services/web/docker-compose.yml down
docker compose -f services/docker-compose.db.yml down
```

## Validación Final

1. **Acceso web:** http://localhost:8200
2. **Login:** `sosadmin` / `Admin123!`
3. **Verificar versión:** Pie de página debe mostrar "4.4.10+"
4. **Verificar PHP:** Administración del sitio > Servidor > Entorno
5. **Verificar cron:** Administración del sitio > Servidor > Tareas programadas

## Resultado

- ✅ **Moodle 4.4.10+ LTS** (versión estable)
- ✅ **PHP 8.2.29** (soporte hasta diciembre 2026)
- ✅ **Base de datos migrada** (sin pérdida de datos)
- ✅ **Funcionalidades preservadas**
- ✅ **Seguridad mejorada** (sin vulnerabilidades conocidas)

## Notas Importantes

1. **Backups:** Siempre crear backups antes de cada upgrade
2. **Plugins obsoletos:** Algunos plugins de 3.10 no son compatibles con versiones superiores
3. **Tema:** Se fuerza el tema `boost` para compatibilidad
4. **PHP:** Configurar `max_input_vars=5000` para upgrades
5. **Base de datos:** Usar parámetros optimizados para dumps grandes

## Troubleshooting

### Error: "Variable 'time_zone' can't be set to the value of 'NULL'"
**Solución:** Usar preámbulo SQL con variables de sesión definidas

### Error: "Lost connection to server during query"
**Solución:** Aumentar parámetros de MariaDB (`max_allowed_packet`, `innodb_buffer_pool_size`)

### Error: "max_input_vars exceeded"
**Solución:** Configurar `max_input_vars=5000` en PHP

### Error: "Mezcla de versiones"
**Solución:** Limpiar completamente el directorio moodle antes del upgrade
