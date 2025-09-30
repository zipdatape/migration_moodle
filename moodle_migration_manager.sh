#!/bin/bash

# Moodle Migration Manager - Menú Interactivo
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
CURRENT_VERSION=""
TARGET_VERSION=""
MOODLE_BACKUP=""
DB_DUMP=""
CONFIG_FILE=""

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
    echo "    MOODLE MIGRATION MANAGER - MENÚ INTERACTIVO"
    echo "=================================================="
    echo -e "${NC}"
    echo -e "${CYAN}Versión: 1.0${NC}"
    echo -e "${CYAN}Fecha: $(date +'%Y-%m-%d %H:%M:%S')${NC}"
    echo
}

# Función para mostrar el menú principal
show_main_menu() {
    echo -e "${BLUE}=== MENÚ PRINCIPAL ===${NC}"
    echo "1. Analizar backup de Moodle"
    echo "2. Configurar rutas de archivos"
    echo "3. Ejecutar migración automática"
    echo "4. Ver estado actual"
    echo "5. Ver logs de migración"
    echo "6. Limpiar entorno"
    echo "7. Ayuda"
    echo "8. Salir"
    echo
}

# Función para analizar backup de Moodle
analyze_moodle_backup() {
    echo -e "${BLUE}=== ANÁLISIS DE BACKUP DE MOODLE ===${NC}"
    
    if [[ -z "$MOODLE_BACKUP" ]]; then
        read -p "Ingresa la ruta del backup de Moodle (.tar.gz): " MOODLE_BACKUP
    fi
    
    if [[ ! -f "$MOODLE_BACKUP" ]]; then
        error "El archivo de backup no existe: $MOODLE_BACKUP"
        return 1
    fi
    
    log "Analizando backup: $MOODLE_BACKUP"
    
    # Crear directorio temporal para análisis
    TEMP_DIR="/tmp/moodle_analysis_$$"
    mkdir -p "$TEMP_DIR"
    
    # Extraer backup temporalmente
    log "Extrayendo backup para análisis..."
    tar -xzf "$MOODLE_BACKUP" -C "$TEMP_DIR" 2>/dev/null || {
        error "Error al extraer el backup"
        rm -rf "$TEMP_DIR"
        return 1
    }
    
    # Buscar directorio moodle
    MOODLE_DIR=""
    for dir in "$TEMP_DIR"/*; do
        if [[ -d "$dir" && -f "$dir/version.php" ]]; then
            MOODLE_DIR="$dir"
            break
        fi
    done
    
    if [[ -z "$MOODLE_DIR" ]]; then
        error "No se encontró el directorio moodle en el backup"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Analizar versión
    log "Analizando versión de Moodle..."
    VERSION_INFO=$(grep -E '^\$version|\$release' "$MOODLE_DIR/version.php" 2>/dev/null || echo "")
    
    if [[ -n "$VERSION_INFO" ]]; then
        echo -e "${GREEN}=== INFORMACIÓN ENCONTRADA ===${NC}"
        echo "$VERSION_INFO"
        echo
        
        # Extraer versión numérica
        VERSION_NUM=$(echo "$VERSION_INFO" | grep '\$version' | sed 's/.*= *\([0-9]*\).*/\1/')
        RELEASE_NAME=$(echo "$VERSION_INFO" | grep '\$release' | sed "s/.*= *'\([^']*\)'.*/\1/")
        
        CURRENT_VERSION="$RELEASE_NAME"
        
        echo -e "${CYAN}Versión detectada: $CURRENT_VERSION${NC}"
        echo -e "${CYAN}Versión numérica: $VERSION_NUM${NC}"
        
        # Determinar versión objetivo
        if [[ "$VERSION_NUM" -lt 2021051700 ]]; then
            TARGET_VERSION="4.5 LTS"
            echo -e "${YELLOW}Recomendación: Migrar a Moodle 4.5 LTS${NC}"
        elif [[ "$VERSION_NUM" -lt 2022112800 ]]; then
            TARGET_VERSION="4.5 LTS"
            echo -e "${YELLOW}Recomendación: Migrar a Moodle 4.5 LTS${NC}"
        elif [[ "$VERSION_NUM" -lt 2024042200 ]]; then
            TARGET_VERSION="4.5 LTS"
            echo -e "${YELLOW}Recomendación: Migrar a Moodle 4.5 LTS${NC}"
        else
            echo -e "${GREEN}Versión actual es reciente${NC}"
        fi
        
        # Buscar config.php
        if [[ -f "$MOODLE_DIR/config.php" ]]; then
            CONFIG_FILE="$MOODLE_DIR/config.php"
            echo -e "${GREEN}Config.php encontrado${NC}"
            
            # Analizar configuración de base de datos
            DB_HOST=$(grep -E 'dbhost' "$CONFIG_FILE" | sed "s/.*= *'\([^']*\)'.*/\1/" | head -1)
            DB_NAME=$(grep -E 'dbname' "$CONFIG_FILE" | sed "s/.*= *'\([^']*\)'.*/\1/" | head -1)
            DB_PREFIX=$(grep -E 'prefix' "$CONFIG_FILE" | sed "s/.*= *'\([^']*\)'.*/\1/" | head -1)
            
            echo -e "${CYAN}Base de datos: $DB_NAME${NC}"
            echo -e "${CYAN}Host: $DB_HOST${NC}"
            echo -e "${CYAN}Prefijo: $DB_PREFIX${NC}"
        fi
        
        # Buscar moodledata
        MOODLEDATA_DIR=""
        for dir in "$TEMP_DIR"/*; do
            if [[ -d "$dir" && -f "$dir/version.php" ]]; then
                continue
            elif [[ -d "$dir" && -f "$dir/version.txt" ]]; then
                MOODLEDATA_DIR="$dir"
                break
            fi
        done
        
        if [[ -n "$MOODLEDATA_DIR" ]]; then
            echo -e "${GREEN}Moodledata encontrado${NC}"
        fi
        
    else
        error "No se pudo determinar la versión de Moodle"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Limpiar directorio temporal
    rm -rf "$TEMP_DIR"
    
    echo
    success "Análisis completado"
    return 0
}

# Función para configurar rutas
configure_paths() {
    echo -e "${BLUE}=== CONFIGURACIÓN DE RUTAS ===${NC}"
    
    # Backup de Moodle
    if [[ -z "$MOODLE_BACKUP" ]]; then
        read -p "Ruta del backup de Moodle (.tar.gz): " MOODLE_BACKUP
    else
        read -p "Ruta del backup de Moodle (.tar.gz) [$MOODLE_BACKUP]: " input
        MOODLE_BACKUP=${input:-$MOODLE_BACKUP}
    fi
    
    # Dump de base de datos
    if [[ -z "$DB_DUMP" ]]; then
        read -p "Ruta del dump de base de datos (.sql): " DB_DUMP
    else
        read -p "Ruta del dump de base de datos (.sql) [$DB_DUMP]: " input
        DB_DUMP=${input:-$DB_DUMP}
    fi
    
    # Validar archivos
    if [[ ! -f "$MOODLE_BACKUP" ]]; then
        error "El archivo de backup de Moodle no existe: $MOODLE_BACKUP"
        return 1
    fi
    
    if [[ ! -f "$DB_DUMP" ]]; then
        error "El archivo de dump de base de datos no existe: $DB_DUMP"
        return 1
    fi
    
    echo
    success "Rutas configuradas correctamente"
    echo -e "${CYAN}Backup Moodle: $MOODLE_BACKUP${NC}"
    echo -e "${CYAN}Dump DB: $DB_DUMP${NC}"
    
    return 0
}

# Función para mostrar estado actual
show_current_status() {
    echo -e "${BLUE}=== ESTADO ACTUAL ===${NC}"
    
    if [[ -n "$CURRENT_VERSION" ]]; then
        echo -e "${GREEN}Versión detectada: $CURRENT_VERSION${NC}"
    else
        echo -e "${YELLOW}Versión no detectada${NC}"
    fi
    
    if [[ -n "$TARGET_VERSION" ]]; then
        echo -e "${GREEN}Versión objetivo: $TARGET_VERSION${NC}"
    else
        echo -e "${YELLOW}Versión objetivo no definida${NC}"
    fi
    
    if [[ -n "$MOODLE_BACKUP" ]]; then
        echo -e "${GREEN}Backup Moodle: $MOODLE_BACKUP${NC}"
    else
        echo -e "${YELLOW}Backup Moodle: No configurado${NC}"
    fi
    
    if [[ -n "$DB_DUMP" ]]; then
        echo -e "${GREEN}Dump DB: $DB_DUMP${NC}"
    else
        echo -e "${YELLOW}Dump DB: No configurado${NC}"
    fi
    
    # Verificar servicios Docker
    echo
    echo -e "${BLUE}=== SERVICIOS DOCKER ===${NC}"
    
    if docker ps | grep -q "moodle_staging_web"; then
        echo -e "${GREEN}Servicio web: Activo${NC}"
        WEB_VERSION=$(docker exec moodle_staging_web php -r 'include "version.php"; echo $release;' 2>/dev/null || echo "No disponible")
        echo -e "${CYAN}Versión web: $WEB_VERSION${NC}"
    else
        echo -e "${YELLOW}Servicio web: Inactivo${NC}"
    fi
    
    if docker ps | grep -q "moodle_staging_mariadb"; then
        echo -e "${GREEN}Servicio DB: Activo${NC}"
    else
        echo -e "${YELLOW}Servicio DB: Inactivo${NC}"
    fi
    
    echo
}

# Función para ejecutar migración
run_migration() {
    echo -e "${BLUE}=== EJECUTAR MIGRACIÓN ===${NC}"
    
    # Verificar configuración
    if [[ -z "$MOODLE_BACKUP" || -z "$DB_DUMP" ]]; then
        error "Debes configurar las rutas primero (opción 2)"
        return 1
    fi
    
    if [[ -z "$CURRENT_VERSION" ]]; then
        error "Debes analizar el backup primero (opción 1)"
        return 1
    fi
    
    # Mostrar resumen
    echo -e "${CYAN}=== RESUMEN DE MIGRACIÓN ===${NC}"
    echo "Versión actual: $CURRENT_VERSION"
    echo "Versión objetivo: $TARGET_VERSION"
    echo "Backup Moodle: $MOODLE_BACKUP"
    echo "Dump DB: $DB_DUMP"
    echo
    
    # Confirmar
    read -p "¿Continuar con la migración? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Migración cancelada"
        return 0
    fi
    
    # Ejecutar script de migración
    log "Ejecutando script de migración automática..."
    
    if [[ -f "$BASE_DIR/migrate_moodle.sh" ]]; then
        # Crear archivo de configuración temporal
        cat > "$BASE_DIR/migration_config.conf" << EOF
MOODLE_BACKUP="$MOODLE_BACKUP"
DB_DUMP="$DB_DUMP"
CURRENT_VERSION="$CURRENT_VERSION"
TARGET_VERSION="$TARGET_VERSION"
EOF
        
        # Ejecutar migración
        cd "$BASE_DIR"
        ./migrate_moodle.sh
        
        # Verificar resultado
        if [[ $? -eq 0 ]]; then
            success "Migración completada exitosamente"
            
            # Actualizar estado
            if docker ps | grep -q "moodle_staging_web"; then
                CURRENT_VERSION=$(docker exec moodle_staging_web php -r 'include "version.php"; echo $release;' 2>/dev/null || echo "No disponible")
                echo -e "${GREEN}Nueva versión: $CURRENT_VERSION${NC}"
            fi
        else
            error "Error en la migración"
        fi
    else
        error "Script de migración no encontrado: $BASE_DIR/migrate_moodle.sh"
    fi
    
    echo
    read -p "Presiona Enter para continuar..."
}

# Función para ver logs
view_logs() {
    echo -e "${BLUE}=== LOGS DE MIGRACIÓN ===${NC}"
    
    if [[ -f "$BASE_DIR/migration.log" ]]; then
        echo -e "${CYAN}Últimas 50 líneas del log:${NC}"
        tail -n 50 "$BASE_DIR/migration.log"
    else
        echo -e "${YELLOW}No hay logs de migración disponibles${NC}"
    fi
    
    echo
    echo -e "${CYAN}Logs de Docker:${NC}"
    
    if docker ps | grep -q "moodle_staging_web"; then
        echo -e "${GREEN}=== LOGS DEL SERVICIO WEB ===${NC}"
        docker logs --tail=20 moodle_staging_web
    fi
    
    if docker ps | grep -q "moodle_staging_mariadb"; then
        echo -e "${GREEN}=== LOGS DEL SERVICIO DB ===${NC}"
        docker logs --tail=20 moodle_staging_mariadb
    fi
    
    echo
    read -p "Presiona Enter para continuar..."
}

# Función para limpiar entorno
clean_environment() {
    echo -e "${BLUE}=== LIMPIAR ENTORNO ===${NC}"
    
    warn "Esta acción detendrá todos los servicios y eliminará los contenedores"
    read -p "¿Estás seguro? [y/N]: " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Deteniendo servicios..."
        
        # Detener servicios
        cd "$BASE_DIR/services"
        docker-compose -f docker-compose.db.yml down 2>/dev/null || true
        cd web
        docker-compose down 2>/dev/null || true
        
        # Limpiar contenedores
        docker rm -f moodle_staging_web moodle_staging_mariadb 2>/dev/null || true
        
        # Limpiar volúmenes
        docker volume rm moodle_staging_mariadb_data 2>/dev/null || true
        
        # Limpiar red
        docker network rm moodle_net 2>/dev/null || true
        
        # Limpiar archivos temporales
        rm -f "$BASE_DIR/migration_config.conf"
        rm -f "$BASE_DIR/migration.log"
        
        success "Entorno limpiado"
    else
        info "Operación cancelada"
    fi
    
    echo
    read -p "Presiona Enter para continuar..."
}

# Función de ayuda
show_help() {
    echo -e "${BLUE}=== AYUDA ===${NC}"
    echo
    echo -e "${CYAN}DESCRIPCIÓN:${NC}"
    echo "Este script te ayuda a migrar Moodle de versiones antiguas a 4.4 LTS"
    echo "de manera interactiva y segura."
    echo
    echo -e "${CYAN}FLUJO RECOMENDADO:${NC}"
    echo "1. Analizar backup de Moodle (detecta versión actual)"
    echo "2. Configurar rutas de archivos (backup y dump de DB)"
    echo "3. Ejecutar migración automática"
    echo "4. Verificar estado actual"
    echo
    echo -e "${CYAN}REQUISITOS:${NC}"
    echo "- Docker y Docker Compose instalados"
    echo "- Archivo de backup de Moodle (.tar.gz)"
    echo "- Dump de base de datos (.sql)"
    echo "- Ejecutar como root"
    echo
    echo -e "${CYAN}ARCHIVOS GENERADOS:${NC}"
    echo "- $BASE_DIR/migration_config.conf (configuración)"
    echo "- $BASE_DIR/migration.log (logs de migración)"
    echo "- $BASE_DIR/backups/ (backups automáticos)"
    echo
    echo -e "${CYAN}COMANDOS ÚTILES:${NC}"
    echo "- Ver logs: docker logs moodle_staging_web"
    echo "- Acceder contenedor: docker exec -it moodle_staging_web bash"
    echo "- Reiniciar servicios: docker-compose restart"
    echo
    read -p "Presiona Enter para continuar..."
}

# Función principal del menú
main_menu() {
    while true; do
        show_banner
        show_main_menu
        
        read -p "Selecciona una opción [1-8]: " choice
        echo
        
        case $choice in
            1)
                analyze_moodle_backup
                read -p "Presiona Enter para continuar..."
                ;;
            2)
                configure_paths
                read -p "Presiona Enter para continuar..."
                ;;
            3)
                run_migration
                ;;
            4)
                show_current_status
                read -p "Presiona Enter para continuar..."
                ;;
            5)
                view_logs
                ;;
            6)
                clean_environment
                ;;
            7)
                show_help
                ;;
            8)
                echo -e "${GREEN}¡Hasta luego!${NC}"
                exit 0
                ;;
            *)
                error "Opción inválida. Selecciona 1-8."
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

if ! command -v docker-compose &> /dev/null; then
    error "Docker Compose no está instalado"
    exit 1
fi

# Crear directorio base si no existe
mkdir -p "$BASE_DIR"

# Ejecutar menú principal
main_menu
