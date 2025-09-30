#!/bin/bash

# Script de Migración Automática Moodle 3.10 → 4.5 LTS
# Fecha: $(date +%Y-%m-%d)

set -e  # Salir en caso de error

# Redirigir output a log si se ejecuta desde el manager
if [[ -f "migration_config.conf" ]]; then
    exec > >(tee -a migration.log) 2>&1
fi

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Función para confirmación
confirm() {
    read -p "$(echo -e ${YELLOW}$1${NC}) [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        error "Operación cancelada por el usuario"
    fi
}

# Banner
echo -e "${BLUE}"
echo "=================================================="
echo "  MIGRACIÓN MOODLE 3.10 → 4.4 LTS AUTOMÁTICA"
echo "=================================================="
echo -e "${NC}"

# Verificar que se ejecute como root
if [[ $EUID -ne 0 ]]; then
   error "Este script debe ejecutarse como root"
fi

# Verificar Docker
if ! command -v docker &> /dev/null; then
    error "Docker no está instalado"
fi

if ! command -v docker-compose &> /dev/null; then
    error "Docker Compose no está instalado"
fi

log "Verificaciones iniciales completadas"

# =============================================================================
# CONFIGURACIÓN
# =============================================================================

# Cargar configuración desde archivo si existe
if [[ -f "migration_config.conf" ]]; then
    log "Cargando configuración desde migration_config.conf"
    source migration_config.conf
fi

# Configuración por defecto
LOCAL_IP=${LOCAL_IP:-localhost}
WEB_PORT=${WEB_PORT:-8200}
DB_PORT=${DB_PORT:-3307}
BASE_DIR=${BASE_DIR:-/root/docker/moodle_staging}
DB_NAME=${DB_NAME:-desa_dbcunix_desacapaolacefs}
TABLE_PREFIX=${TABLE_PREFIX:-mco_}
ADMIN_USER=${ADMIN_USER:-sosadmin}
ADMIN_PASS=${ADMIN_PASS:-Admin123!}

# Si no hay configuración, usar modo interactivo
if [[ -z "$MOODLE_BACKUP" || -z "$DB_DUMP" ]]; then
    echo -e "${BLUE}=== CONFIGURACIÓN INTERACTIVA ===${NC}"
    
    # IP local
    read -p "Ingresa la IP local del servidor [localhost]: " LOCAL_IP
    LOCAL_IP=${LOCAL_IP:-localhost}
    
    # Puerto web
    read -p "Ingresa el puerto para el servicio web [8200]: " WEB_PORT
    WEB_PORT=${WEB_PORT:-8200}
    
    # Puerto base de datos
    read -p "Ingresa el puerto para MariaDB [3307]: " DB_PORT
    DB_PORT=${DB_PORT:-3307}
    
    # Directorio base
    read -p "Ingresa el directorio base para la migración [/root/docker/moodle_staging]: " BASE_DIR
    BASE_DIR=${BASE_DIR:-/root/docker/moodle_staging}
    
    # Ruta del backup de Moodle
    read -p "Ingresa la ruta completa del backup de Moodle (.tar.gz): " MOODLE_BACKUP
    if [[ ! -f "$MOODLE_BACKUP" ]]; then
        error "El archivo de backup de Moodle no existe: $MOODLE_BACKUP"
    fi
    
    # Ruta del dump de base de datos
    read -p "Ingresa la ruta completa del dump de base de datos (.sql): " DB_DUMP
    if [[ ! -f "$DB_DUMP" ]]; then
        error "El archivo de dump de base de datos no existe: $DB_DUMP"
    fi
    
    # Nombre de la base de datos
    read -p "Ingresa el nombre de la base de datos [desa_dbcunix_desacapaolacefs]: " DB_NAME
    DB_NAME=${DB_NAME:-desa_dbcunix_desacapaolacefs}
    
    # Prefijo de tablas
    read -p "Ingresa el prefijo de tablas [mco_]: " TABLE_PREFIX
    TABLE_PREFIX=${TABLE_PREFIX:-mco_}
    
    # Usuario administrador
    read -p "Ingresa el nombre del usuario administrador [sosadmin]: " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-sosadmin}
    
    # Contraseña administrador
    read -p "Ingresa la contraseña del administrador [Admin123!]: " ADMIN_PASS
    ADMIN_PASS=${ADMIN_PASS:-Admin123!}
    
    # Confirmar configuración
    echo -e "${BLUE}=== RESUMEN DE CONFIGURACIÓN ===${NC}"
    echo "IP Local: $LOCAL_IP"
    echo "Puerto Web: $WEB_PORT"
    echo "Puerto DB: $DB_PORT"
    echo "Directorio Base: $BASE_DIR"
    echo "Backup Moodle: $MOODLE_BACKUP"
    echo "Dump DB: $DB_DUMP"
    echo "Base de Datos: $DB_NAME"
    echo "Prefijo Tablas: $TABLE_PREFIX"
    echo "Usuario Admin: $ADMIN_USER"
    echo "Contraseña Admin: $ADMIN_PASS"
    echo
    
    confirm "¿Continuar con esta configuración?"
else
    log "Usando configuración predefinida"
fi

# =============================================================================
# PREPARACIÓN DEL ENTORNO
# =============================================================================

log "Creando estructura de directorios"
mkdir -p "$BASE_DIR"/{services/{web,db},db_init,db_splits,html,backups}

# =============================================================================
# CONFIGURACIÓN DE DOCKER
# =============================================================================

log "Creando archivos de configuración Docker"

# Docker Compose para MariaDB
cat > "$BASE_DIR/services/docker-compose.db.yml" << EOF
version: "3.9"
services:
  mariadb:
    image: mariadb:10.6
    container_name: moodle_staging_mariadb
    environment:
      - MARIADB_ROOT_PASSWORD=
      - MARIADB_DATABASE=$DB_NAME
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
      - "$DB_PORT:3306"

volumes:
  mariadb_data:

networks:
  moodle_net:
    driver: bridge
EOF

# Dockerfile para PHP 7.4 (versión inicial)
cat > "$BASE_DIR/services/web/Dockerfile" << 'EOF'
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
EOF

# Docker Compose para Web
cat > "$BASE_DIR/services/web/docker-compose.yml" << EOF
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
      - "$WEB_PORT:80"
    depends_on:
      - mariadb

networks:
  moodle_net:
    external: true
EOF

# =============================================================================
# PREPARACIÓN DE LA BASE DE DATOS
# =============================================================================

log "Preparando base de datos"

# Copiar dump a db_init
cp "$DB_DUMP" "$BASE_DIR/db_init/01_dump.sql"

# Crear preámbulo SQL
cat > "$BASE_DIR/db_splits/preambulo.sql" << 'EOF'
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS;
SET FOREIGN_KEY_CHECKS=0;
SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS;
SET UNIQUE_CHECKS=0;
SET @OLD_TIME_ZONE=@@TIME_ZONE;
SET TIME_ZONE='+00:00';
SET @saved_cs_client=@@character_set_client;
SET character_set_client = utf8mb4;
EOF

# =============================================================================
# DESCOMPRESIÓN DE MOODLE
# =============================================================================

log "Descomprimiendo backup de Moodle"
cd "$BASE_DIR"

# Extraer backup de Moodle
tar -xzf "$MOODLE_BACKUP" -C html/

# Verificar estructura
if [[ ! -d "html/moodle" ]]; then
    error "No se encontró el directorio 'moodle' en el backup"
fi

if [[ ! -d "html/moodledata" ]]; then
    error "No se encontró el directorio 'moodledata' en el backup"
fi

# =============================================================================
# CONFIGURACIÓN DE MOODLE
# =============================================================================

log "Configurando Moodle"

# Crear config.php
cat > "html/moodle/config.php" << EOF
<?php
unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

\$CFG->dbtype    = 'mariadb';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = 'mariadb';
\$CFG->dbname    = '$DB_NAME';
\$CFG->dbuser    = 'root';
\$CFG->dbpass    = '';
\$CFG->prefix    = '$TABLE_PREFIX';
\$CFG->dboptions = array(
    'dbpersist' => 0,
    'dbport' => 3306,
    'dbsocket' => '',
    'dbcollation' => 'utf8mb4_unicode_ci',
);

\$CFG->wwwroot   = 'http://$LOCAL_IP:$WEB_PORT';
\$CFG->dataroot  = '/var/www/moodledata';
\$CFG->admin     = 'admin';
\$CFG->directorypermissions = 0777;
\$CFG->sslproxy = false;
\$CFG->theme = 'boost';

require_once(__DIR__ . '/lib/setup.php');
EOF

# =============================================================================
# INICIO DE SERVICIOS
# =============================================================================

log "Iniciando servicios Docker"

# Crear red externa
docker network create moodle_net 2>/dev/null || true

# Iniciar MariaDB
cd "$BASE_DIR/services"
docker-compose -f docker-compose.db.yml up -d

# Esperar a que MariaDB esté listo
log "Esperando a que MariaDB esté listo..."
sleep 10

# Verificar que MariaDB esté funcionando
if ! docker exec moodle_staging_mariadb mysqladmin ping -h localhost --silent; then
    error "MariaDB no está respondiendo"
fi

# Iniciar servicio web
cd "$BASE_DIR/services/web"
docker-compose up -d

# Esperar a que el servicio web esté listo
log "Esperando a que el servicio web esté listo..."
sleep 5

# =============================================================================
# IMPORTACIÓN DE BASE DE DATOS
# =============================================================================

log "Importando base de datos"

# Verificar si el dump es muy grande y necesita división
DUMP_SIZE=$(stat -c%s "$BASE_DIR/db_init/01_dump.sql")
if [[ $DUMP_SIZE -gt 100000000 ]]; then  # 100MB
    warn "Dump grande detectado ($DUMP_SIZE bytes). Dividiendo en partes..."
    
    # Dividir dump
    cd "$BASE_DIR/db_splits"
    csplit -f part_ -b '%03d.sql' ../db_init/01_dump.sql '/^-- Table structure for table/' '{*}' 2>/dev/null || true
    
    # Crear header
    head -n 50 ../db_init/01_dump.sql > header.sql
    
    # Importar concatenando
    cat preambulo.sql header.sql part_*.sql | \
    docker exec -i moodle_staging_mariadb bash -lc \
    "mysql -uroot --password= --default-character-set=utf8mb4 --max_allowed_packet=1073741824 $DB_NAME"
else
    # Importar directamente
    docker exec -i moodle_staging_mariadb bash -lc \
    "mysql -uroot --password= --default-character-set=utf8mb4 $DB_NAME" < "$BASE_DIR/db_init/01_dump.sql"
fi

# =============================================================================
# CONFIGURACIÓN INICIAL DE MOODLE
# =============================================================================

log "Configurando Moodle inicial"

# Configurar PHP
docker exec moodle_staging_web bash -c "printf '%s\n' 'max_input_vars=5000' > /usr/local/etc/php/conf.d/moodle.ini && apachectl -k restart"

# Asignar permisos
chown -R 33:33 "$BASE_DIR/html/moodle"

# =============================================================================
# RESET DE CONTRASEÑA DE ADMINISTRADOR
# =============================================================================

log "Configurando usuario administrador"

# Buscar usuario admin
ADMIN_USER_FOUND=$(docker exec moodle_staging_mariadb bash -lc "mysql -uroot --password= -D $DB_NAME -e \"SELECT username FROM ${TABLE_PREFIX}user WHERE deleted=0 AND suspended=0 ORDER BY id LIMIT 1;\" -s -N" 2>/dev/null || echo "")

if [[ -n "$ADMIN_USER_FOUND" ]]; then
    log "Usuario administrador encontrado: $ADMIN_USER_FOUND"
    ADMIN_USER="$ADMIN_USER_FOUND"
else
    warn "No se encontró usuario administrador, usando: $ADMIN_USER"
fi

# Resetear contraseña
docker exec moodle_staging_web bash -lc "php admin/cli/reset_password.php --username=$ADMIN_USER --password=$ADMIN_PASS" || warn "No se pudo resetear la contraseña"

# =============================================================================
# MIGRACIÓN PROGRESIVA DE MOODLE
# =============================================================================

log "Iniciando migración progresiva de Moodle"

# URLs de descarga
MOODLE_311_URL="https://github.com/moodle/moodle/archive/refs/heads/MOODLE_311_STABLE.tar.gz"
MOODLE_401_URL="https://github.com/moodle/moodle/archive/refs/heads/MOODLE_401_STABLE.tar.gz"
MOODLE_404_URL="https://github.com/moodle/moodle/archive/refs/heads/MOODLE_404_STABLE.tar.gz"
MOODLE_405_URL="https://github.com/moodle/moodle/archive/refs/heads/MOODLE_405_STABLE.tar.gz"

# Función para backup
backup_before_upgrade() {
    local version=$1
    log "Creando backup antes del upgrade a $version"
    
    # Backup de base de datos
    docker exec moodle_staging_mariadb bash -lc "mysqldump -uroot --password= --single-transaction --routines --events --triggers $DB_NAME" > "$BASE_DIR/backups/moodle_${version}_before_upgrade.sql"
    
    # Backup de moodledata
    tar -czf "$BASE_DIR/backups/moodledata_${version}_before_upgrade.tar.gz" -C "$BASE_DIR/html" moodledata
}

# Función para upgrade
upgrade_moodle() {
    local version=$1
    local url=$2
    local php_version=$3
    
    log "Upgrading a Moodle $version (PHP $php_version)"
    
    # Backup
    backup_before_upgrade "$version"
    
    # Activar mantenimiento
    docker exec moodle_staging_web bash -lc "php admin/cli/maintenance.php --enable" || true
    
    # Actualizar PHP si es necesario
    log "Actualizando PHP a $php_version"
    sed -i "s/php:[0-9]\+\.[0-9]\+-apache/php:${php_version}-apache/g" "$BASE_DIR/services/web/Dockerfile"
    cd "$BASE_DIR/services/web"
    docker-compose build --no-cache
    docker-compose up -d
    sleep 5
    
    # Descargar Moodle
    log "Descargando Moodle $version"
    cd "$BASE_DIR"
    curl -L -o "moodle-${version}.tgz" "$url"
    tar -xzf "moodle-${version}.tgz"
    
    # Reemplazar core
    local moodle_dir="moodle-MOODLE_${version}_STABLE"
    if [[ ! -d "$moodle_dir" ]]; then
        error "No se pudo extraer Moodle $version"
    fi
    
    # Backup del config.php actual
    cp "html/moodle/config.php" "config.php.backup"
    
    # Reemplazar directorio
    rm -rf "html/moodle"
    mv "$moodle_dir" "html/moodle"
    cp "config.php.backup" "html/moodle/config.php"
    
    # Asignar permisos
    chown -R 33:33 "html/moodle"
    
    # Configurar PHP
    docker exec moodle_staging_web bash -c "printf '%s\n' 'max_input_vars=5000' > /usr/local/etc/php/conf.d/moodle.ini && apachectl -k restart"
    
    # Ejecutar upgrade
    log "Ejecutando upgrade CLI"
    docker exec moodle_staging_web bash -c "cd /var/www/html && php admin/cli/upgrade.php --non-interactive"
    
    # Desactivar mantenimiento
    docker exec moodle_staging_web bash -c "cd /var/www/html && php admin/cli/maintenance.php --disable"
    
    # Purgar cachés
    docker exec moodle_staging_web bash -c "cd /var/www/html && php admin/cli/purge_caches.php"
    
    log "Upgrade a Moodle $version completado"
}

# Ejecutar migraciones progresivas
log "Iniciando migración progresiva de Moodle"

# 1. Moodle 3.10 → 3.11 (PHP 7.4)
log "=== ETAPA 1: Moodle 3.10 → 3.11 (PHP 7.4) ==="
upgrade_moodle "3.11" "$MOODLE_311_URL" "7.4"

# 2. Moodle 3.11 → 4.1 LTS (PHP 8.0)
log "=== ETAPA 2: Moodle 3.11 → 4.1 LTS (PHP 8.0) ==="
upgrade_moodle "4.1" "$MOODLE_401_URL" "8.0"

# 3. Moodle 4.1 → 4.4 LTS (PHP 8.2)
log "=== ETAPA 3: Moodle 4.1 → 4.4 LTS (PHP 8.2) ==="
upgrade_moodle "4.4" "$MOODLE_404_URL" "8.2"

# 4. Moodle 4.4 → 4.5 LTS (PHP 8.2)
log "=== ETAPA 4: Moodle 4.4 → 4.5 LTS (PHP 8.2) ==="
upgrade_moodle "4.5" "$MOODLE_405_URL" "8.2"

# =============================================================================
# CONFIGURACIÓN FINAL
# =============================================================================

log "Configuración final"

# Ejecutar cron
docker exec moodle_staging_web bash -c "cd /var/www/html && php admin/cli/cron.php --keep-alive=1" || warn "Error en cron"

# Verificar versión final
FINAL_VERSION=$(docker exec moodle_staging_web bash -c "cd /var/www/html && php -r 'include \"version.php\"; echo \"\$release\";'")
FINAL_PHP=$(docker exec moodle_staging_web bash -c "php -v | head -1")

# =============================================================================
# RESUMEN FINAL
# =============================================================================

echo -e "${GREEN}"
echo "=================================================="
echo "  MIGRACIÓN COMPLETADA EXITOSAMENTE"
echo "=================================================="
echo -e "${NC}"

echo -e "${BLUE}=== INFORMACIÓN DE ACCESO ===${NC}"
echo "URL: http://$LOCAL_IP:$WEB_PORT"
echo "Usuario: $ADMIN_USER"
echo "Contraseña: $ADMIN_PASS"
echo

echo -e "${BLUE}=== VERSIÓN FINAL ===${NC}"
echo "Moodle: $FINAL_VERSION"
echo "PHP: $FINAL_PHP"
echo

echo -e "${BLUE}=== COMANDOS ÚTILES ===${NC}"
echo "Ver logs web: docker logs moodle_staging_web"
echo "Ver logs DB: docker logs moodle_staging_mariadb"
echo "Acceder web: docker exec -it moodle_staging_web bash"
echo "Acceder DB: docker exec -it moodle_staging_mariadb bash"
echo "Parar servicios: cd $BASE_DIR/services && docker-compose -f docker-compose.db.yml down && cd web && docker-compose down"
echo

echo -e "${BLUE}=== VALIDACIÓN RECOMENDADA ===${NC}"
echo "1. Acceder a http://$LOCAL_IP:$WEB_PORT"
echo "2. Iniciar sesión con $ADMIN_USER / $ADMIN_PASS"
echo "3. Verificar que el pie de página muestre la versión correcta"
echo "4. Navegar por el tablero y cursos"
echo "5. Verificar cron en Administración del sitio > Servidor > Tareas programadas"
echo

log "Migración completada. ¡Disfruta tu nuevo Moodle 4.5 LTS!"
