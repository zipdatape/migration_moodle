#!/bin/bash

# Database Manager - Gestor de Base de Datos para Moodle
# Autor: Asistente IA
# Fecha: $(date +%Y-%m-%d)

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variables globales
BASE_DIR="/root/docker/moodle_staging"
DB_DUMP=""
DB_NAME=""
DB_PREFIX=""
DB_HOST="localhost"
DB_PORT="3307"
DB_USER="root"
DB_PASS=""
CONTAINER_NAME="moodle_staging_mariadb"

# Función para logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Banner principal
show_banner() {
    clear
    echo -e "${PURPLE}"
    echo "=================================================="
    echo "    DATABASE MANAGER - GESTOR DE BASE DE DATOS"
    echo "=================================================="
    echo -e "${NC}"
    echo -e "${CYAN}Versión: 1.0${NC}"
    echo -e "${CYAN}Fecha: $(date +'%Y-%m-%d %H:%M:%S')${NC}"
    echo
}

# Función para mostrar el menú principal
show_main_menu() {
    echo -e "${BLUE}=== MENÚ PRINCIPAL ===${NC}"
    echo "1. Analizar dump de base de datos"
    echo "2. Configurar conexión a base de datos"
    echo "3. Importar base de datos"
    echo "4. Dividir dump grande"
    echo "5. Validar importación"
    echo "6. Optimizar base de datos"
    echo "7. Backup de base de datos"
    echo "8. Restaurar desde backup"
    echo "9. Ver estado de base de datos"
    echo "10. Limpiar base de datos"
    echo "11. Ayuda"
    echo "12. Salir"
    echo
}

# Función para analizar dump de base de datos
analyze_db_dump() {
    echo -e "${BLUE}=== ANÁLISIS DE DUMP DE BASE DE DATOS ===${NC}"
    
    if [[ -z "$DB_DUMP" ]]; then
        read -p "Ingresa la ruta del dump de base de datos (.sql): " DB_DUMP
    fi
    
    if [[ ! -f "$DB_DUMP" ]]; then
        error "El archivo de dump no existe: $DB_DUMP"
        return 1
    fi
    
    log "Analizando dump: $DB_DUMP"
    
    # Información básica del archivo
    FILE_SIZE=$(stat -c%s "$DB_DUMP")
    FILE_SIZE_MB=$((FILE_SIZE / 1024 / 1024))
    
    echo -e "${CYAN}=== INFORMACIÓN DEL ARCHIVO ===${NC}"
    echo "Archivo: $DB_DUMP"
    echo "Tamaño: $FILE_SIZE_MB MB"
    echo "Fecha: $(stat -c%y "$DB_DUMP")"
    echo
    
    # Analizar contenido del dump
    log "Analizando contenido del dump..."
    
    # Detectar tipo de dump
    if grep -q "MariaDB dump" "$DB_DUMP"; then
        DUMP_TYPE="MariaDB"
    elif grep -q "MySQL dump" "$DB_DUMP"; then
        DUMP_TYPE="MySQL"
    else
        DUMP_TYPE="Desconocido"
    fi
    
    # Detectar versión
    VERSION=$(grep -E "Server version|MariaDB" "$DB_DUMP" | head -1 | sed 's/.*Server version: \([0-9.]*\).*/\1/' || echo "No detectada")
    
    # Detectar base de datos
    DB_NAME_DETECTED=$(grep -E "CREATE DATABASE|USE " "$DB_DUMP" | head -1 | sed "s/.*CREATE DATABASE.*\`\([^`]*\)\`.*/\1/" | sed "s/.*USE \`\([^`]*\)\`.*/\1/" || echo "No detectada")
    
    # Detectar prefijo de tablas
    PREFIX_DETECTED=$(grep -E "CREATE TABLE.*\`" "$DB_DUMP" | head -5 | sed 's/.*CREATE TABLE.*\`\([^`]*\)_.*\`.*/\1_/' | sort -u | head -1 || echo "No detectado")
    
    # Contar tablas
    TABLE_COUNT=$(grep -c "CREATE TABLE" "$DB_DUMP" || echo "0")
    
    # Detectar caracteres especiales
    CHARSET=$(grep -E "CHARACTER SET|charset" "$DB_DUMP" | head -1 | sed 's/.*CHARACTER SET \([^;]*\).*/\1/' | sed 's/.*charset=\([^;]*\).*/\1/' || echo "No detectado")
    
    # Detectar collation
    COLLATION=$(grep -E "COLLATE|collate" "$DB_DUMP" | head -1 | sed 's/.*COLLATE \([^;]*\).*/\1/' | sed 's/.*collate=\([^;]*\).*/\1/' || echo "No detectado")
    
    echo -e "${CYAN}=== INFORMACIÓN DEL DUMP ===${NC}"
    echo "Tipo: $DUMP_TYPE"
    echo "Versión: $VERSION"
    echo "Base de datos: $DB_NAME_DETECTED"
    echo "Prefijo de tablas: $PREFIX_DETECTED"
    echo "Número de tablas: $TABLE_COUNT"
    echo "Charset: $CHARSET"
    echo "Collation: $COLLATION"
    echo
    
    # Detectar problemas potenciales
    echo -e "${CYAN}=== ANÁLISIS DE PROBLEMAS ===${NC}"
    
    if [[ $FILE_SIZE_MB -gt 100 ]]; then
        warn "Dump grande detectado ($FILE_SIZE_MB MB). Se recomienda dividir en partes."
    fi
    
    if grep -q "SET FOREIGN_KEY_CHECKS=0" "$DB_DUMP"; then
        info "Dump contiene desactivación de foreign key checks"
    else
        warn "Dump no contiene desactivación de foreign key checks"
    fi
    
    if grep -q "SET UNIQUE_CHECKS=0" "$DB_DUMP"; then
        info "Dump contiene desactivación de unique checks"
    else
        warn "Dump no contiene desactivación de unique checks"
    fi
    
    if grep -q "SET TIME_ZONE" "$DB_DUMP"; then
        info "Dump contiene configuración de timezone"
    else
        warn "Dump no contiene configuración de timezone"
    fi
    
    # Detectar tablas problemáticas
    PROBLEMATIC_TABLES=$(grep -E "CREATE TABLE.*\`.*\`" "$DB_DUMP" | grep -E "(mdl_|mco_|prefix_)" | wc -l)
    if [[ $PROBLEMATIC_TABLES -gt 0 ]]; then
        info "Se detectaron $PROBLEMATIC_TABLES tablas con prefijo"
    fi
    
    # Recomendaciones
    echo
    echo -e "${CYAN}=== RECOMENDACIONES ===${NC}"
    
    if [[ $FILE_SIZE_MB -gt 100 ]]; then
        echo "• Usar opción 4 para dividir el dump en partes"
    fi
    
    if [[ "$CHARSET" != "utf8mb4" ]]; then
        echo "• Considerar convertir a utf8mb4 para mejor compatibilidad"
    fi
    
    if [[ -z "$PREFIX_DETECTED" ]]; then
        echo "• Verificar prefijo de tablas en la configuración de Moodle"
    fi
    
    echo "• Usar opción 3 para importar la base de datos"
    echo "• Usar opción 5 para validar la importación"
    
    # Guardar información detectada
    DB_NAME=${DB_NAME_DETECTED:-$DB_NAME}
    DB_PREFIX=${PREFIX_DETECTED:-$DB_PREFIX}
    
    echo
    success "Análisis completado"
    return 0
}

# Función para configurar conexión
configure_db_connection() {
    echo -e "${BLUE}=== CONFIGURACIÓN DE CONEXIÓN ===${NC}"
    
    # Host
    read -p "Host de la base de datos [$DB_HOST]: " input
    DB_HOST=${input:-$DB_HOST}
    
    # Puerto
    read -p "Puerto de la base de datos [$DB_PORT]: " input
    DB_PORT=${input:-$DB_PORT}
    
    # Usuario
    read -p "Usuario de la base de datos [$DB_USER]: " input
    DB_USER=${input:-$DB_USER}
    
    # Contraseña
    read -s -p "Contraseña de la base de datos: " DB_PASS
    echo
    
    # Nombre de la base de datos
    read -p "Nombre de la base de datos [$DB_NAME]: " input
    DB_NAME=${input:-$DB_NAME}
    
    # Prefijo de tablas
    read -p "Prefijo de tablas [$DB_PREFIX]: " input
    DB_PREFIX=${input:-$DB_PREFIX}
    
    # Nombre del contenedor
    read -p "Nombre del contenedor [$CONTAINER_NAME]: " input
    CONTAINER_NAME=${input:-$CONTAINER_NAME}
    
    echo
    success "Configuración guardada"
    echo -e "${CYAN}Host: $DB_HOST:$DB_PORT${NC}"
    echo -e "${CYAN}Usuario: $DB_USER${NC}"
    echo -e "${CYAN}Base de datos: $DB_NAME${NC}"
    echo -e "${CYAN}Prefijo: $DB_PREFIX${NC}"
    echo -e "${CYAN}Contenedor: $CONTAINER_NAME${NC}"
    
    return 0
}

# Función para importar base de datos
import_database() {
    echo -e "${BLUE}=== IMPORTAR BASE DE DATOS ===${NC}"
    
    # Verificar configuración
    if [[ -z "$DB_DUMP" || -z "$DB_NAME" ]]; then
        error "Debes configurar el dump y la base de datos primero"
        return 1
    fi
    
    if [[ ! -f "$DB_DUMP" ]]; then
        error "El archivo de dump no existe: $DB_DUMP"
        return 1
    fi
    
    # Verificar que el contenedor esté ejecutándose
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        error "El contenedor $CONTAINER_NAME no está ejecutándose"
        return 1
    fi
    
    # Verificar tamaño del dump
    FILE_SIZE=$(stat -c%s "$DB_DUMP")
    FILE_SIZE_MB=$((FILE_SIZE / 1024 / 1024))
    
    echo -e "${CYAN}=== INFORMACIÓN DE IMPORTACIÓN ===${NC}"
    echo "Dump: $DB_DUMP"
    echo "Tamaño: $FILE_SIZE_MB MB"
    echo "Base de datos: $DB_NAME"
    echo "Contenedor: $CONTAINER_NAME"
    echo
    
    # Confirmar importación
    read -p "¿Continuar con la importación? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Importación cancelada"
        return 0
    fi
    
    log "Iniciando importación de base de datos..."
    
    # Crear base de datos si no existe
    log "Creando base de datos si no existe..."
    docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || {
        error "Error al crear la base de datos"
        return 1
    }
    
    # Importar según el tamaño
    if [[ $FILE_SIZE_MB -gt 100 ]]; then
        warn "Dump grande detectado. Usando método optimizado..."
        import_large_dump
    else
        log "Importando dump directamente..."
        import_small_dump
    fi
    
    # Verificar importación
    log "Verificando importación..."
    TABLE_COUNT=$(docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SHOW TABLES;" -s -N | wc -l)
    
    if [[ $TABLE_COUNT -gt 0 ]]; then
        success "Importación completada. $TABLE_COUNT tablas importadas."
    else
        error "Error en la importación. No se detectaron tablas."
        return 1
    fi
    
    return 0
}

# Función para importar dump pequeño
import_small_dump() {
    log "Importando dump pequeño..."
    
    # Crear preámbulo si no existe
    if [[ ! -f "$BASE_DIR/db_splits/preambulo.sql" ]]; then
        mkdir -p "$BASE_DIR/db_splits"
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
    fi
    
    # Importar con preámbulo
    cat "$BASE_DIR/db_splits/preambulo.sql" "$DB_DUMP" | \
    docker exec -i "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" --default-character-set=utf8mb4 --max_allowed_packet=1073741824 "$DB_NAME"
}

# Función para importar dump grande
import_large_dump() {
    log "Importando dump grande..."
    
    # Crear directorio para divisiones
    mkdir -p "$BASE_DIR/db_splits"
    
    # Crear preámbulo
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
    
    # Dividir dump
    log "Dividiendo dump en partes..."
    cd "$BASE_DIR/db_splits"
    csplit -f part_ -b '%03d.sql' "$DB_DUMP" '/^-- Table structure for table/' '{*}' 2>/dev/null || true
    
    # Crear header
    head -n 50 "$DB_DUMP" > header.sql
    
    # Importar concatenando
    log "Importando partes concatenadas..."
    cat preambulo.sql header.sql part_*.sql | \
    docker exec -i "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" --default-character-set=utf8mb4 --max_allowed_packet=1073741824 "$DB_NAME"
    
    # Limpiar archivos temporales
    rm -f part_*.sql header.sql
}

# Función para dividir dump grande
split_large_dump() {
    echo -e "${BLUE}=== DIVIDIR DUMP GRANDE ===${NC}"
    
    if [[ -z "$DB_DUMP" ]]; then
        read -p "Ingresa la ruta del dump de base de datos (.sql): " DB_DUMP
    fi
    
    if [[ ! -f "$DB_DUMP" ]]; then
        error "El archivo de dump no existe: $DB_DUMP"
        return 1
    fi
    
    FILE_SIZE=$(stat -c%s "$DB_DUMP")
    FILE_SIZE_MB=$((FILE_SIZE / 1024 / 1024))
    
    if [[ $FILE_SIZE_MB -lt 50 ]]; then
        warn "El dump es pequeño ($FILE_SIZE_MB MB). No es necesario dividirlo."
        return 0
    fi
    
    log "Dividiendo dump de $FILE_SIZE_MB MB..."
    
    # Crear directorio para divisiones
    mkdir -p "$BASE_DIR/db_splits"
    cd "$BASE_DIR/db_splits"
    
    # Crear preámbulo
    cat > preambulo.sql << 'EOF'
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS;
SET FOREIGN_KEY_CHECKS=0;
SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS;
SET UNIQUE_CHECKS=0;
SET @OLD_TIME_ZONE=@@TIME_ZONE;
SET TIME_ZONE='+00:00';
SET @saved_cs_client=@@character_set_client;
SET character_set_client = utf8mb4;
EOF
    
    # Dividir dump
    log "Dividiendo en partes..."
    csplit -f part_ -b '%03d.sql' "$DB_DUMP" '/^-- Table structure for table/' '{*}' 2>/dev/null || true
    
    # Crear header
    head -n 50 "$DB_DUMP" > header.sql
    
    # Contar partes
    PART_COUNT=$(ls part_*.sql 2>/dev/null | wc -l)
    
    echo
    success "Dump dividido en $PART_COUNT partes"
    echo -e "${CYAN}Partes creadas en: $BASE_DIR/db_splits/${NC}"
    echo -e "${CYAN}Archivos: preambulo.sql, header.sql, part_*.sql${NC}"
    
    return 0
}

# Función para validar importación
validate_import() {
    echo -e "${BLUE}=== VALIDAR IMPORTACIÓN ===${NC}"
    
    if [[ -z "$DB_NAME" ]]; then
        error "Debes configurar el nombre de la base de datos primero"
        return 1
    fi
    
    # Verificar que el contenedor esté ejecutándose
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        error "El contenedor $CONTAINER_NAME no está ejecutándose"
        return 1
    fi
    
    log "Validando importación de la base de datos: $DB_NAME"
    
    # Verificar que la base de datos existe
    if ! docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -e "USE \`$DB_NAME\`;" 2>/dev/null; then
        error "La base de datos $DB_NAME no existe"
        return 1
    fi
    
    # Contar tablas
    TABLE_COUNT=$(docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SHOW TABLES;" -s -N | wc -l)
    
    # Obtener información de tablas
    echo -e "${CYAN}=== INFORMACIÓN DE LA BASE DE DATOS ===${NC}"
    echo "Base de datos: $DB_NAME"
    echo "Número de tablas: $TABLE_COUNT"
    echo
    
    if [[ $TABLE_COUNT -eq 0 ]]; then
        error "No se encontraron tablas en la base de datos"
        return 1
    fi
    
    # Verificar tablas de Moodle
    echo -e "${CYAN}=== TABLAS DE MOODLE ===${NC}"
    
    # Buscar tablas comunes de Moodle
    MOODLE_TABLES=("user" "course" "config" "log" "sessions" "files" "context" "role" "capabilities")
    
    for table in "${MOODLE_TABLES[@]}"; do
        if [[ -n "$DB_PREFIX" ]]; then
            TABLE_NAME="${DB_PREFIX}${table}"
        else
            TABLE_NAME="mdl_${table}"
        fi
        
        if docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SHOW TABLES LIKE '$TABLE_NAME';" -s -N | grep -q "$TABLE_NAME"; then
            ROW_COUNT=$(docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SELECT COUNT(*) FROM \`$TABLE_NAME\`;" -s -N)
            echo -e "${GREEN}✓${NC} $TABLE_NAME: $ROW_COUNT registros"
        else
            echo -e "${YELLOW}✗${NC} $TABLE_NAME: No encontrada"
        fi
    done
    
    # Verificar configuración de Moodle
    if [[ -n "$DB_PREFIX" ]]; then
        CONFIG_TABLE="${DB_PREFIX}config"
    else
        CONFIG_TABLE="mdl_config"
    fi
    
    if docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SHOW TABLES LIKE '$CONFIG_TABLE';" -s -N | grep -q "$CONFIG_TABLE"; then
        echo
        echo -e "${CYAN}=== CONFIGURACIÓN DE MOODLE ===${NC}"
        
        # Obtener configuración importante
        docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "
        SELECT name, value FROM \`$CONFIG_TABLE\` 
        WHERE name IN ('version', 'release', 'wwwroot', 'dataroot', 'dbtype', 'dbhost', 'dbname', 'prefix')
        ORDER BY name;" 2>/dev/null || warn "No se pudo obtener la configuración"
    fi
    
    # Verificar integridad
    echo
    echo -e "${CYAN}=== VERIFICACIÓN DE INTEGRIDAD ===${NC}"
    
    # Verificar foreign keys
    FK_ERRORS=$(docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE WHERE REFERENCED_TABLE_SCHEMA = '$DB_NAME' AND REFERENCED_TABLE_NAME IS NOT NULL;" -s -N 2>/dev/null || echo "0")
    echo "Foreign keys: $FK_ERRORS"
    
    # Verificar índices
    INDEX_COUNT=$(docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = '$DB_NAME';" -s -N 2>/dev/null || echo "0")
    echo "Índices: $INDEX_COUNT"
    
    echo
    success "Validación completada"
    return 0
}

# Función para optimizar base de datos
optimize_database() {
    echo -e "${BLUE}=== OPTIMIZAR BASE DE DATOS ===${NC}"
    
    if [[ -z "$DB_NAME" ]]; then
        error "Debes configurar el nombre de la base de datos primero"
        return 1
    fi
    
    # Verificar que el contenedor esté ejecutándose
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        error "El contenedor $CONTAINER_NAME no está ejecutándose"
        return 1
    fi
    
    log "Optimizando base de datos: $DB_NAME"
    
    # Confirmar optimización
    read -p "¿Continuar con la optimización? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Optimización cancelada"
        return 0
    fi
    
    # Optimizar tablas
    log "Optimizando tablas..."
    docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "OPTIMIZE TABLE \`$DB_NAME\`.*;" 2>/dev/null || warn "Error al optimizar algunas tablas"
    
    # Analizar tablas
    log "Analizando tablas..."
    docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "ANALYZE TABLE \`$DB_NAME\`.*;" 2>/dev/null || warn "Error al analizar algunas tablas"
    
    # Reparar tablas
    log "Reparando tablas..."
    docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "REPAIR TABLE \`$DB_NAME\`.*;" 2>/dev/null || warn "Error al reparar algunas tablas"
    
    # Verificar tablas
    log "Verificando tablas..."
    docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "CHECK TABLE \`$DB_NAME\`.*;" 2>/dev/null || warn "Error al verificar algunas tablas"
    
    success "Optimización completada"
    return 0
}

# Función para backup de base de datos
backup_database() {
    echo -e "${BLUE}=== BACKUP DE BASE DE DATOS ===${NC}"
    
    if [[ -z "$DB_NAME" ]]; then
        error "Debes configurar el nombre de la base de datos primero"
        return 1
    fi
    
    # Verificar que el contenedor esté ejecutándose
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        error "El contenedor $CONTAINER_NAME no está ejecutándose"
        return 1
    fi
    
    # Crear directorio de backups
    mkdir -p "$BASE_DIR/backups"
    
    # Generar nombre de backup
    BACKUP_NAME="moodle_db_backup_$(date +%Y%m%d_%H%M%S).sql"
    BACKUP_PATH="$BASE_DIR/backups/$BACKUP_NAME"
    
    log "Creando backup de la base de datos: $DB_NAME"
    echo "Archivo: $BACKUP_PATH"
    
    # Confirmar backup
    read -p "¿Continuar con el backup? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Backup cancelado"
        return 0
    fi
    
    # Crear backup
    log "Ejecutando mysqldump..."
    docker exec "$CONTAINER_NAME" mysqldump -u"$DB_USER" -p"$DB_PASS" \
        --single-transaction \
        --routines \
        --events \
        --triggers \
        --add-drop-table \
        --add-locks \
        --create-options \
        --disable-keys \
        --extended-insert \
        --quick \
        --set-charset \
        "$DB_NAME" > "$BACKUP_PATH"
    
    if [[ $? -eq 0 ]]; then
        BACKUP_SIZE=$(stat -c%s "$BACKUP_PATH")
        BACKUP_SIZE_MB=$((BACKUP_SIZE / 1024 / 1024))
        success "Backup creado exitosamente"
        echo -e "${CYAN}Archivo: $BACKUP_PATH${NC}"
        echo -e "${CYAN}Tamaño: $BACKUP_SIZE_MB MB${NC}"
    else
        error "Error al crear el backup"
        return 1
    fi
    
    return 0
}

# Función para restaurar desde backup
restore_database() {
    echo -e "${BLUE}=== RESTAURAR DESDE BACKUP ===${NC}"
    
    # Listar backups disponibles
    if [[ -d "$BASE_DIR/backups" ]]; then
        echo -e "${CYAN}=== BACKUPS DISPONIBLES ===${NC}"
        ls -la "$BASE_DIR/backups"/*.sql 2>/dev/null | nl || {
            warn "No se encontraron backups"
            return 1
        }
        echo
    else
        warn "No se encontró el directorio de backups"
        return 1
    fi
    
    # Seleccionar backup
    read -p "Ingresa el número del backup a restaurar: " backup_num
    BACKUP_FILE=$(ls "$BASE_DIR/backups"/*.sql 2>/dev/null | sed -n "${backup_num}p")
    
    if [[ -z "$BACKUP_FILE" || ! -f "$BACKUP_FILE" ]]; then
        error "Backup no válido"
        return 1
    fi
    
    echo -e "${CYAN}Backup seleccionado: $BACKUP_FILE${NC}"
    
    # Confirmar restauración
    warn "Esta operación reemplazará completamente la base de datos actual"
    read -p "¿Continuar con la restauración? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Restauración cancelada"
        return 0
    fi
    
    # Verificar que el contenedor esté ejecutándose
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        error "El contenedor $CONTAINER_NAME no está ejecutándose"
        return 1
    fi
    
    log "Restaurando desde backup: $BACKUP_FILE"
    
    # Crear base de datos si no existe
    docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    
    # Restaurar
    docker exec -i "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" --default-character-set=utf8mb4 "$DB_NAME" < "$BACKUP_FILE"
    
    if [[ $? -eq 0 ]]; then
        success "Restauración completada"
    else
        error "Error en la restauración"
        return 1
    fi
    
    return 0
}

# Función para ver estado de base de datos
show_db_status() {
    echo -e "${BLUE}=== ESTADO DE BASE DE DATOS ===${NC}"
    
    # Verificar que el contenedor esté ejecutándose
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        echo -e "${YELLOW}Contenedor: $CONTAINER_NAME (Inactivo)${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Contenedor: $CONTAINER_NAME (Activo)${NC}"
    
    if [[ -n "$DB_NAME" ]]; then
        # Verificar conexión
        if docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -e "USE \`$DB_NAME\`;" 2>/dev/null; then
            echo -e "${GREEN}Base de datos: $DB_NAME (Conectada)${NC}"
            
            # Información de la base de datos
            TABLE_COUNT=$(docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SHOW TABLES;" -s -N | wc -l)
            echo -e "${CYAN}Tablas: $TABLE_COUNT${NC}"
            
            # Tamaño de la base de datos
            DB_SIZE=$(docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'DB Size in MB' FROM information_schema.tables WHERE table_schema='$DB_NAME';" -s -N 2>/dev/null || echo "N/A")
            echo -e "${CYAN}Tamaño: $DB_SIZE MB${NC}"
            
            # Charset y collation
            CHARSET=$(docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SELECT DEFAULT_CHARACTER_SET_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$DB_NAME';" -s -N 2>/dev/null || echo "N/A")
            COLLATION=$(docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SELECT DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$DB_NAME';" -s -N 2>/dev/null || echo "N/A")
            echo -e "${CYAN}Charset: $CHARSET${NC}"
            echo -e "${CYAN}Collation: $COLLATION${NC}"
            
        else
            echo -e "${YELLOW}Base de datos: $DB_NAME (No conectada)${NC}"
        fi
    else
        echo -e "${YELLOW}Base de datos: No configurada${NC}"
    fi
    
    # Información del contenedor
    echo
    echo -e "${CYAN}=== INFORMACIÓN DEL CONTENEDOR ===${NC}"
    docker exec "$CONTAINER_NAME" mysql --version 2>/dev/null || echo "MySQL/MariaDB no disponible"
    
    # Procesos activos
    echo
    echo -e "${CYAN}=== PROCESOS ACTIVOS ===${NC}"
    docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -e "SHOW PROCESSLIST;" 2>/dev/null | head -10 || echo "No se pudieron obtener los procesos"
    
    return 0
}

# Función para limpiar base de datos
clean_database() {
    echo -e "${BLUE}=== LIMPIAR BASE DE DATOS ===${NC}"
    
    if [[ -z "$DB_NAME" ]]; then
        error "Debes configurar el nombre de la base de datos primero"
        return 1
    fi
    
    # Verificar que el contenedor esté ejecutándose
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        error "El contenedor $CONTAINER_NAME no está ejecutándose"
        return 1
    fi
    
    warn "Esta operación eliminará completamente la base de datos: $DB_NAME"
    read -p "¿Estás seguro? [y/N]: " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Eliminando base de datos: $DB_NAME"
        docker exec "$CONTAINER_NAME" mysql -u"$DB_USER" -p"$DB_PASS" -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;"
        success "Base de datos eliminada"
    else
        info "Operación cancelada"
    fi
    
    return 0
}

# Función de ayuda
show_help() {
    echo -e "${BLUE}=== AYUDA ===${NC}"
    echo
    echo -e "${CYAN}DESCRIPCIÓN:${NC}"
    echo "Este script te ayuda a gestionar la base de datos de Moodle"
    echo "de manera segura y eficiente."
    echo
    echo -e "${CYAN}FUNCIONES PRINCIPALES:${NC}"
    echo "1. Analizar dump - Examina el archivo SQL antes de importar"
    echo "2. Configurar conexión - Define parámetros de conexión"
    echo "3. Importar base de datos - Importa el dump a MariaDB"
    echo "4. Dividir dump grande - Divide dumps grandes en partes"
    echo "5. Validar importación - Verifica que la importación sea correcta"
    echo "6. Optimizar base de datos - Optimiza tablas e índices"
    echo "7. Backup de base de datos - Crea backup de la BD actual"
    echo "8. Restaurar desde backup - Restaura desde un backup"
    echo "9. Ver estado - Muestra información del estado actual"
    echo "10. Limpiar base de datos - Elimina la base de datos"
    echo
    echo -e "${CYAN}FLUJO RECOMENDADO:${NC}"
    echo "1. Analizar dump de base de datos"
    echo "2. Configurar conexión a base de datos"
    echo "3. Importar base de datos"
    echo "4. Validar importación"
    echo "5. Optimizar base de datos (opcional)"
    echo
    echo -e "${CYAN}REQUISITOS:${NC}"
    echo "- Docker y Docker Compose instalados"
    echo "- Contenedor MariaDB ejecutándose"
    echo "- Archivo de dump de base de datos (.sql)"
    echo "- Ejecutar como root"
    echo
    echo -e "${CYAN}ARCHIVOS GENERADOS:${NC}"
    echo "- $BASE_DIR/db_splits/ (divisiones de dump)"
    echo "- $BASE_DIR/backups/ (backups de base de datos)"
    echo
    read -p "Presiona Enter para continuar..."
}

# Función principal del menú
main_menu() {
    while true; do
        show_banner
        show_main_menu
        
        read -p "Selecciona una opción [1-12]: " choice
        echo
        
        case $choice in
            1)
                analyze_db_dump
                read -p "Presiona Enter para continuar..."
                ;;
            2)
                configure_db_connection
                read -p "Presiona Enter para continuar..."
                ;;
            3)
                import_database
                read -p "Presiona Enter para continuar..."
                ;;
            4)
                split_large_dump
                read -p "Presiona Enter para continuar..."
                ;;
            5)
                validate_import
                read -p "Presiona Enter para continuar..."
                ;;
            6)
                optimize_database
                read -p "Presiona Enter para continuar..."
                ;;
            7)
                backup_database
                read -p "Presiona Enter para continuar..."
                ;;
            8)
                restore_database
                read -p "Presiona Enter para continuar..."
                ;;
            9)
                show_db_status
                read -p "Presiona Enter para continuar..."
                ;;
            10)
                clean_database
                read -p "Presiona Enter para continuar..."
                ;;
            11)
                show_help
                ;;
            12)
                echo -e "${GREEN}¡Hasta luego!${NC}"
                exit 0
                ;;
            *)
                error "Opción inválida. Selecciona 1-12."
                sleep 2
                ;;
        esac
    done
}

# Verificar que se ejecute como root
if [[ $EUID -ne 0 ]]; then
    error "Este script debe ejecutarse como root"
    exit 1
fi

# Verificar Docker
if ! command -v docker &> /dev/null; then
    error "Docker no está instalado"
    exit 1
fi

# Crear directorio base si no existe
mkdir -p "$BASE_DIR"

# Ejecutar menú principal
main_menu
