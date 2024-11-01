#!/bin/bash

git config --global core.autocrlf false
PROJECT_ROOT_DIR=$(pwd -P)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function check_and_load_scripts() {
  filename_script="$1"

  RED_COLOR='\033[0;31m'     # Cor vermelha para erros
  NO_COLOR='\033[0m'         # Cor neutra para resetar as cores no terminal

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  scriptsh="$script_dir/${filename_script}"

  if [ ! -f "$scriptsh" ]; then
    echo -e "$RED_COLOR DANG: Shell script $scriptsh não existe.\nEsse arquivo possui as funções utilitárias necessárias.\nImpossível continuar!$NO_COLOR"
    exit 1
  else
    source "$scriptsh"
  fi
}

# Carrega o arquivo externo com as funções
check_and_load_scripts "/scripts/utils.sh"
#check_and_load_scripts "/scripts/create_template_testdb.sh"
check_and_load_scripts "/scripts/read_ini.sh"
check_and_load_scripts "install.sh"

if ! verifica_instalacao; then
    echo_error "Utilitário docker service não instalado!
    Acesse o diretório \"sdocker\" e
    execute o comando ./install.sh"
    exit 1
fi

PROJECT_DJANGO='DJANGO'
PROJECT_DEV_DIR=$PROJECT_ROOT_DIR
PROJECT_NAME=$(basename $PROJECT_ROOT_DIR)
DEFAULT_BASE_DIR="$PROJECT_ROOT_DIR/$PROJECT_NAME"
INIFILE_PATH="${SCRIPT_DIR}/config.ini"
LOCAL_INIFILE_PATH="${SCRIPT_DIR}/config-local.ini"

if [ ! -f "$LOCAL_INIFILE_PATH" ]; then
  echo ">>> cp ${SCRIPT_DIR}/config-local-sample.ini $LOCAL_INIFILE_PATH"
  cp "${SCRIPT_DIR}/config-local-sample.ini" "$LOCAL_INIFILE_PATH"
fi


command="generate-project"
arg_command=$1
if [ "$PROJECT_ROOT_DIR" = "$SCRIPT_DIR" ] && [ "$arg_command" == "$command" ]; then
  shift
  option=$*
  extension_generate_project "$INIFILE_PATH" $command $option

elif [ "$PROJECT_ROOT_DIR" = "$SCRIPT_DIR" ]; then
  echo_success "Configurações iniciais do script definidas com sucesso."
  echo_info "Execute o comando \"sdocker\" no diretório raiz do seu projeto.
  ou use a opção \"generate-project\""
  exit 1
else
  result=$(verificar_comando_inicializacao_ambiente_dev "$PROJECT_ROOT_DIR")
  _return_func=$?  # Captura o valor de retorno da função
  read TIPO_PROJECT mensagem <<< "$result"

  if [ $_return_func -eq 1 ]; then
      echo_error "Ambiente de desenvolvimento não identificado."
      echo_info "Execute o comando \"sdocker\" no diretório raiz do seu projeto."
      exit 1
  fi
fi
TIPO_PROJECT=${TIPO_PROJECT:-PROJECT_DJANGO}

############## Tratamento env file ##############
filename_path=$(get_filename_path "$PROJECT_DEV_DIR" "$LOCAL_INIFILE_PATH" "envfile" "$PROJECT_NAME")
PROJECT_ENV_PATH_FILE="${filename_path:-.env}"

filename_path=$(get_filename_path "$PROJECT_DEV_DIR" "$LOCAL_INIFILE_PATH" "envfile_sample" "$PROJECT_NAME" )
PROJECT_ENV_FILE_SAMPLE="${filename_path:-.env.sample}"

_project_file=$(read_ini "$LOCAL_INIFILE_PATH" "envfile" "$PROJECT_NAME" | tr -d '\r')
if [ "$(dirname $PROJECT_ENV_FILE_SAMPLE)" != "$(dirname $PROJECT_ENV_PATH_FILE)" ] && [ -z "$PROJECT_ENV_PATH_FILE" ] ; then
  echo_error "O diretório do arquivo .env é diferente do arquivo $(basename $PROJECT_ENV_FILE_SAMPLE). Impossível continuar"
  echo_warning "Informe o path do arquivo .env nas configurações do \"sdocker\".
  Para isso, adicione a linha <<nome_projeto>>=<<path_arquivo_env_sample>> na seção \"[envfile]\" no arquivo de
  configuração ${LOCAL_INIFILE_PATH}.
  Exemplo: ${PROJECT_NAME}=$(dirname $PROJECT_ENV_FILE_SAMPLE)/.env"
  exit 1
fi

############## Tratamento Dockerfile ##############
filename_path=$(get_filename_path "$PROJECT_DEV_DIR" "$INIFILE_PATH" "dockerfile" "$PROJECT_NAME")
DEFAULT_PROJECT_DOCKERFILE=$filename_path

filename_path=$(get_filename_path "$PROJECT_DEV_DIR" "$INIFILE_PATH" "dockerfile_sample" "$PROJECT_NAME")
DEFAULT_PROJECT_DOCKERFILE_SAMPLE=$filename_path

############## Tratamento docker-compose ##############
filename_path=$(get_filename_path "$PROJECT_DEV_DIR" "$INIFILE_PATH" "dockercompose" "$PROJECT_NAME")
DEFAULT_PROJECT_DOCKERCOMPOSE=$filename_path

filename_path=$(get_filename_path "$PROJECT_DEV_DIR" "$INIFILE_PATH" "dockercompose_sample" "$PROJECT_NAME")
DEFAULT_PROJECT_DOCKERCOMPOSE_SAMPLE=$filename_path

##############################################################################
### FUÇÕES UTILITÁRIAS
##############################################################################
function get_server_name() {
  local _input="$1"

  # Verifique se a entrada está vazia
  if [ -z "$_input" ]; then
    return 1
  fi

  _service_name_parse=$(dict_get "$_input" "${DICT_ARG_SERVICE_PARSE[*]}")
  echo "${_service_name_parse:-$_input}"
}

##############################################################################
### GERANDO ARQUIVO ENV SAMPLE PERSONALIZADO
##############################################################################
function verifica_e_configura_env() {
    local project_env_file_sample="$1"
    local default_project_dockerfile="$2"
    local project_name="$3"
    local config_inifile="$4"

    # Função para verificar e retornar o caminho correto do arquivo de requirements
    function get_requirements_file() {
        # Verificar se o arquivo requirements.txt existe
        if [ -f "$project_root_dir/requirements.txt" ]; then
            echo "requirements.txt"
            return
        fi

        # Verificar se o arquivo requirements/dev.txt existe
        if [ -f "$project_root_dir/requirements/dev.txt" ]; then
            echo "requirements/dev.txt"
            return
        fi

        # Verificar se o arquivo requirements/development.txt existe
        if [ -f "$project_root_dir/requirements/development.txt" ]; then
            echo "requirements/development.txt"
            return
        fi

        # Caso nenhum arquivo seja encontrado, retornar uma string vazia
        echo ""
    }

    # Definir variáveis de ambiente
    local default_requirements_file #SC2155
    project_root_dir="$(pwd -P)"
    local default_base_dir="$project_root_dir/$project_name"
    local settings_local_file_sample="local_settings_sample.py"

    # A estrutura ${VAR/old/new} substitui a primeira ocorrência de old na variável VAR por new
    # Removendo a plavra "_sample". Ex. local_settings_sample.py irá ficar local_settings.py
    local settings_local_file="${settings_local_file_sample/_sample/}"

    local default_requirements_file #SC2155
    default_requirements_file="$(get_requirements_file $project_root_dir)"

    # Verificar se o arquivo de exemplo de ambiente existe
    if [ ! -f "${project_env_file_sample}" ]; then
        echo_error "Arquivo ${project_env_file_sample} não encontrado. Impossível continuar!"
        echo_info "Esse arquivo é o modelo com as configurações mínimas necessárias para os containers funcionarem.
       Deseja que este script GERE um arquivo modelo padrão para seu projeto?"
        read -p "Pressione 'S' para confirmar ou [ENTER] para ignorar: " resposta
        resposta=$(echo "$resposta" | tr '[:lower:]' '[:upper:]')  # Converter para maiúsculas

        if [ "$resposta" = "S" ]; then
          resultado=$(determinar_gateway_vpn)
          default_vpn_gateway_faixa_ip=$(echo "$resultado" | cut -d ' ' -f 1)
          default_vpn_gateway_ip=$(echo "$resultado" | cut -d ' ' -f 2)

# Criar  arquivo env sample e inserir as variáveis na ordem inversa
cat <<EOF > "$project_env_file_sample"
REVISADO=false
LOGINFO=false

COMPOSE_PROJECT_NAME=${project_name}
DEV_IMAGE=
PYTHON_BASE_IMAGE=python:3.12-slim-bullseye
POSTGRES_IMAGE=postgres:16.3

APP_PORT=8000
POSTGRES_EXTERNAL_PORT=5432
REDIS_EXTERNAL_PORT=6379
PGADMIN_EXTERNAL_PORT=8001

DATABASE_NAME=${project_name}
DATABASE_USER=postgres
DATABASE_PASSWORD=postgres
DATABASE_HOST=db
DATABASE_PORT=5432
DATABASE_DUMP_DIR=${project_root_dir}/dump

GIT_BRANCH_MAIN=master
REQUIREMENTS_FILE=${default_requirements_file}

SETTINGS_LOCAL_FILE_SAMPLE=${settings_local_file_sample}
SETTINGS_LOCAL_FILE=${settings_local_file}
BASE_DIR=${default_base_dir}

WORK_DIR=/opt/app

DOCKERFILE=${default_project_dockerfile}

USER_NAME=$(id -un)
USER_UID=$(id -u)
USER_GID=$(id -g)

VPN_GATEWAY=${default_vpn_gateway_ip}
VPN_GATEWAY_FAIXA_IP=${default_vpn_gateway_faixa_ip}

BEHAVE_CHROME_WEBDRIVER=/usr/local/bin/chromedriver
BEHAVE_BROWSER=chrome
BEHAVE_CHROME_HEADLESS=True
SELENIUM_GRID_HUB_URL=http://selenium_grid:4444/wd/hub
TEMPLATE_TESTDB=template_testdb


COMPOSES_FILES="
all:docker-compose.yml
"

SERVICES_COMMANDS="
all:deploy;undeploy;redeploy;status;restart;logs;up;down
web:makemigrations;manage;migrate;shell_plus;debug;build;git;pre-commit;test_behave
db:psql;wait;dump;restore;copy;build
pgadmin:
redis:
selenium_grid:
"

SERVICES_DEPENDENCIES="
django:node;redis;db
pgadmin:db
"

ARG_SERVICE_PARSE="
web:django
"
EOF
            echo_success "Arquivo $project_env_file_sample criado."
        fi
    fi

    # Verificar novamente se o arquivo de ambiente foi criado
    if [ ! -f "${project_env_file_sample}" ]; then
        echo_error "Arquivo ${project_env_file_sample} não encontrado. Impossível continuar!"
        echo_warning "Ter um modelo de um arquivo \".env\" faz parte da arquitetura do  \"sdocker\".
        Há duas soluções para resolver isso:
        1. Adicionar o arquivo $project_env_file_sample no diretório raiz (${project_root_dir}) do seu projeto.
        2. Informar o path do arquivo nas configurações do \"sdocker\".
        Para isso, adicione a linha <<nome_projeto>>=<<path_arquivo_env_sample>> na seção \"[envfile_sample]\" no arquivo de
        configuração ${config_inifile}.
        Exemplo: ${project_name}=${project_root_dir}/.env.dev.sample"
        exit 1
    fi
}

if [ "$PROJECT_ROOT_DIR" != "$SCRIPT_DIR" ]; then
  verifica_e_configura_env "$PROJECT_ENV_FILE_SAMPLE" "$DEFAULT_PROJECT_DOCKERFILE" "$PROJECT_NAME" "$INIFILE_PATH"
fi
##############################################################################
### EXPORTANDO VARIÁVEIS DE AMBIENTE DO ARQUIVO ENV
##############################################################################
configura_env() {
  local project_env_file_sample="$1"
  local project_env_path_file="$2"

  # Verifica se o arquivo env NÃO existe e se o env sample EXISTE,
  # se sim, procede com a cópia do arquivo env sample para env
  if [ ! -f "${project_env_path_file}" ] && [ -f "${project_env_file_sample}" ]; then
    echo ">>> cp ${project_env_file_sample}  ${project_env_path_file}"
    cp "${project_env_file_sample}" "${project_env_path_file}"
  fi

  sleep .5

  # Exporta as variáveis de ambiente presentes no arquivo env
  export $(xargs -0 < "${project_env_path_file}") 2> /dev/null

  # Carrega o conteúdo do arquivo env diretamente no script
  # &>/dev/null: Redireciona tanto a saída padrão (stdout) quanto a saída de erro (stderr) para /dev/null, que é um "buraco negro" no SO
  # Silenciar completamente qualquer tipo de saída do comando.
  source "${project_env_path_file}" &>/dev/null

  # Imprime as variáveis de ambiente
#  imprime_variaveis_env "${project_env_path_file}"
}

if [ "$PROJECT_ROOT_DIR" != "$SCRIPT_DIR" ]; then
  configura_env "$PROJECT_ENV_FILE_SAMPLE" "$PROJECT_ENV_PATH_FILE"
  _return_func=$?
  if [ "$_return_func" -ne 0 ]; then
    echo_error "Problema relacionado ao conteúdo do arquivo .env."
    echo_warning "Certifique-se de que o arquivo .env está formatado corretamente, especialmente
    para variáveis multilinha, que devem ser delimitadas corretamente. O uso de aspas (\") ou
    barras invertidas (\\) para indicar continuação de linha deve ser consistente.
    "
    exit 1
  fi
fi
##############################################################################
### CONVERTENDO ARRAY DO .ENV NA TAD DICT
##############################################################################
# Declarações das variáveis de arrays
DICT_COMPOSES_FILES=()
DICT_SERVICES_COMMANDS=()
DICT_SERVICES_DEPENDENCIES=()
DICT_ARG_SERVICE_PARSE=()

#Conversão das string multilinhas para array
convert_multiline_to_array "$COMPOSES_FILES" DICT_COMPOSES_FILES
convert_multiline_to_array "$SERVICES_COMMANDS" DICT_SERVICES_COMMANDS
convert_multiline_to_array "$SERVICES_DEPENDENCIES" DICT_SERVICES_DEPENDENCIES
convert_multiline_to_array "$ARG_SERVICE_PARSE" DICT_ARG_SERVICE_PARSE

get_dependent_services() {
    local service_name="$1"  # O nome do serviço passado como argumento
    local -n ref_name_services="$2"  # Nome da variável de array passada por referência

    # Obtem os serviços que dependem de $service_name e armazena no array passado por referência
    dict_get_and_convert "$service_name" "${DICT_SERVICES_DEPENDENCIES[*]}" ref_name_services

## Exemplo de uso
#declare -a _name_services  # Declara o array onde o resultado será armazenado
#
## Chama a função passando o nome do serviço e o array por referência
#get_dependent_services "service_name_exemplo" _name_services
#
## Exibe o conteúdo do array após a chamada
#echo "Serviços que dependem de service_name_exemplo:"
#for service in "${_name_services[@]}"; do
#    echo "$service"
#done
}
##############################################################################
### DEFINIÇÕES DE VARIÁVEIS GLOBAIS
##############################################################################

LOGINFO=${LOGINFO:-false}
REVISADO=${REVISADO:-false}

BEHAVE_CHROME_WEBDRIVER="${BEHAVE_CHROME_WEBDRIVER:-/usr/local/bin/chromedriver}"
BEHAVE_BROWSER="${BEHAVE_BROWSER:-chrome}"
BEHAVE_CHROME_HEADLESS="${BEHAVE_CHROME_HEADLESS:-True}"
SELENIUM_GRID_HUB_URL="${SELENIUM_GRID_HUB_URL:-http://selenium_grid:4444/wd/hub}"
TEMPLATE_TESTDB="${TEMPLATE_TESTDB:-template_testdb}"

COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$PROJECT_NAME}"
GIT_BRANCH_MAIN=${GIT_BRANCH_MAIN:-master}
REQUIREMENTS_FILE_HELP=""
if [ -f "$REQUIREMENTS_FILE" ]; then
  REQUIREMENTS_FILE_HELP="
          O valor da variável REQUIREMENTS_FILE deve apontar para o diretorio, se existir, e arquivo requiriments.
            Exemplo: REQUIREMENTS_FILE=requiriments/dev.txt
          Se o arquivo requirements.txt estiver na raiz do diretório do projeto, basta informar o nome.
            Exemplo: REQUIREMENTS_FILE=requiriments.txt
  "
fi
REQUIREMENTS_FILE="${REQUIREMENTS_FILE:-requirements.txt}"

BASE_DIR=${BASE_DIR:-$DEFAULT_BASE_DIR}
SETTINGS_LOCAL_FILE_SAMPLE="${SETTINGS_LOCAL_FILE_SAMPLE:-local_settings_sample.py}"
# A estrutura ${VAR/old/new} substitui a primeira ocorrência de old na variável VAR por new
# Removendo a plavra "_sample". Ex. local_settings_sample.py irá ficar  local_settings.py
DEFAULT_SETTINGS_LOCAL_FILE=${SETTINGS_LOCAL_FILE_SAMPLE/_sample/}
SETTINGS_LOCAL_FILE=${SETTINGS_LOCAL_FILE:-$DEFAULT_SETTINGS_LOCAL_FILE}

DATABASE_NAME=${DATABASE_NAME:-$COMPOSE_PROJECT_NAME}
POSTGRES_USER=${DATABASE_USER:-$POSTGRES_USER}
POSTGRES_PASSWORD=${DATABASE_PASSWORD:-$POSTGRES_PASSWORD}
POSTGRES_DB=${DATABASE_NAME:-$POSTGRES_DB}
POSTGRES_HOST=${DATABASE_HOST:-$POSTGRES_HOST}
POSTGRES_PORT=${DATABASE_PORT:-$POSTGRES_PORT}
POSTGRES_EXTERNAL_PORT=${POSTGRES_EXTERNAL_PORT:-$POSTGRES_PORT}
#POSTGRESQL="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/"
POSTGRES_DUMP_DIR=${DATABASE_DUMP_DIR:-dump}
DIR_DUMP=${POSTGRES_DUMP_DIR:-dump}

WORK_DIR="${WORK_DIR:-/opt/app}"

PROJECT_DOCKERFILE="${DOCKERFILE:-$DEFAULT_PROJECT_DOCKERFILE}"
# Obtendo o nome do Dockerfile sample a partir do diretório de $PROJECT_DOCKERFILE e
# filename de  $PROJECT_DOCKERFILE_SAMPLE
PROJECT_DOCKERFILE_SAMPLE="$(dirname $PROJECT_DOCKERFILE)/$(basename $DEFAULT_PROJECT_DOCKERFILE_SAMPLE)"

# Tratamento para obter o path do docker-compose
dockercompose=$(dict_get "all" "${DICT_COMPOSES_FILES[*]}")

if [ ! -f "$dockercompose" ]; then
  dirpath="$(dirname $dockercompose)"
  if [ "$dirpath" = "." ]; then
    dirpath="$(dirname $PROJECT_ENV_PATH_FILE)"
    dockercompose="${dirpath}/${dockercompose}"
  fi
fi

PROJECT_DOCKERCOMPOSE="${dockercompose:-$DEFAULT_PROJECT_DOCKERCOMPOSE}"
PROJECT_DOCKERCOMPOSE_SAMPLE="$(dirname $PROJECT_DOCKERCOMPOSE)/$(basename $DEFAULT_PROJECT_DOCKERCOMPOSE_SAMPLE)"

PYTHON_BASE_IMAGE="${PYTHON_BASE_IMAGE:-3.12-slim-bullseye}"
#DEV_IMAGE="${DEV_IMAGE:-python-nodejs-base}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:16.3}"

APP_PORT=${APP_PORT:-8000}
REDIS_PORT=${REDIS_PORT:-6379}
REDIS_EXTERNAL_PORT=${REDIS_EXTERNAL_PORT:-6379}
PGADMIN_EXTERNAL_PORT=${PGADMIN_EXTERNAL_PORT:-8001}

USER_NAME=${USER_NAME:-$(id -un)}
USER_UID=${USER_UID:-$(id -u)}
USER_GID=${USER_GID:-$(id -g)}

VPN_GATEWAY_FAIXA_IP="${VPN_GATEWAY_FAIXA_IP:-172.19.0.0/16}"
VPN_GATEWAY="${VPN_GATEWAY:-172.19.0.2}"
ROUTE_NETWORK="${ROUTE_NETWORK:-<<enderero_ip/faixa>> -- Exemplo: 10.10.0.0/16}"
DOMAIN_NAME="${DOMAIN_NAME:-<<url_dns_banco_externo>> -- Exemplo: route.domain.local}"
DATABASE_REMOTE_HOST="${DATABASE_REMOTE_HOST:-<<nome_do_banco_externo>> -- Exemplo: banco_remoto}"

ETC_HOSTS_HELP=""
if [ -z "$ETC_HOSTS" ]; then
          ETC_HOSTS_HELP="
           \"
           <<url_dns_host_banco_externo>>:<<ip_host_banco_externo>>
           <<url_dns_host_externo>>:<<ip_host_externo>>
           ...
           \"
          Exemplo:
            ETC_HOSTS=\"
            route.domain.local:10.10.0.144
            \"
    "
fi

COMMANDS_COMUNS=(up down restart exec run logs shell)

ARG_SERVICE="$1"
ARG_COMMAND="$2"
ARG_OPTIONS="${@:3}"
#SERVICE_NAME=$(get_server_name "${ARG_SERVICE}")
SERVICE_WEB_NAME=$(get_server_name "web")
SERVICE_DB_NAME=$(get_server_name "db")

if [ "$PROJECT_ROOT_DIR" != "$SCRIPT_DIR" ]; then
  result=$(verificar_comando_inicializacao_ambiente_dev "$PROJECT_ROOT_DIR")
  _return_func=$?  # Captura o valor de retorno da função
  read tipo_projeto mensagem <<< "$result"


  echo_info "PROJECT_ROOT_DIR: $PROJECT_ROOT_DIR"
  echo_info "$mensagem"
  if [ -f "$PROJECT_DOCKERFILE" ]; then
    echo_info "Arquivo com instruções para criar imagem do contêiner da app: $PROJECT_DOCKERFILE"
  fi
  if [ -f "$PROJECT_DOCKERFILE_SAMPLE" ]; then
    echo_info "Arquivo: modelo Dockerfile: $PROJECT_DOCKERFILE_SAMPLE"
  fi
  if [ -f "$PROJECT_DOCKERCOMPOSE" ]; then
    echo_info "Arquivo de definição que configura os serviços de um aplicativo Docker multi-container: $PROJECT_DOCKERCOMPOSE"
  fi
  if [ -f "$PROJECT_DOCKERCOMPOSE_SAMPLE" ]; then
    echo_info "Arquivo modelo docker-compose.yml sample: $PROJECT_DOCKERCOMPOSE_SAMPLE"
  fi
  if [ -f "$PROJECT_ENV_PATH_FILE" ]; then
    echo_info "Arquivo com definição de variáveis de ambiente utilizado pelo docker-compose: $PROJECT_ENV_PATH_FILE"
  fi
  if [ -f "$PROJECT_ENV_FILE_SAMPLE" ]; then
    echo_info "Arquivo modelo .env: $PROJECT_ENV_FILE_SAMPLE"
  fi
fi

##############################################################################
### Tratamento para os arquivos docker-compose-base.yml, docker-compose.yml e Dockerfile
##############################################################################
function copy_docker_compose_base() {
  local config_inifile="$1"
  local docker_compose_path="$2"

  dockercompose_base=$(read_ini "$config_inifile" "dockercompose" "python_base" | tr -d '\r')
  project_dockercompose_base_path="$(dirname $docker_compose_path)/${dockercompose_base}"
  if [ ! -f "$project_dockercompose_base_path" ] && [ -f "$project_dockercompose_base_path.sample" ]; then
    echo ">>> cp $project_dockercompose_base_path.sample $project_dockercompose_base_path"
    cp "$project_dockercompose_base_path.sample" "$project_dockercompose_base_path"
  fi

  # Extrair o path usando grep e sed
  path_volume_script=$(grep -oP '(?<=- ).*(?=:/scripts/)' "$project_dockercompose_base_path")
  path_script_dir=$SCRIPT_DIR/scripts/
  if [ -f "$project_dockercompose_base_path" ] && [ "$path_volume_script" != "$path_script_dir" ]; then
    echo "9999 path_volume_script=$path_volume_script"

    dockerfile_postgresql=$(read_ini "$config_inifile" "dockerfile" "postgresql" | tr -d '\r')
    dockerfile_postgresql_path=$SCRIPT_DIR/dockerfiles/${dockerfile_postgresql}
    # Ajustando o path do build dockerfile do container "postgresql" (db)
    # Substituir linhas contendo "Dockerfile-db" pelo novo texto
    novo_texto="      dockerfile: ${dockerfile_postgresql_path}"
    sed -i "/$dockerfile_postgresql/c\\$novo_texto" "$project_dockercompose_base_path"

    # Ajustando o volume do container "postgresql" (db)
    # Comando sed para substituir a linha inteira que contém ":/scripts/" pelo novo texto
    novo_texto="      - ${path_script_dir}:/scripts/"
    sed -i "/:\/scripts\//c\\$novo_texto" "$project_dockercompose_base_path"

    # Ajustando o volume do container "postgresql" (db)
    # Comando sed para substituir a linha inteira que contém "docker-entrypoint-initdb.d" pelo novo texto
    novo_texto="      - ${path_script_dir}init_database.sh:/docker-entrypoint-initdb.d/init_database.sh"
    sed -i "/docker-entrypoint-initdb.d/c\\$novo_texto" "$project_dockercompose_base_path"
  fi
}

function verifica_e_configura_dockerfile_project() {
  local tipo="$1"  #dockerfile, docker-compose
  local env_file_path="$2"
  local docker_file_path="$3"
  local docker_file_or_compose_path="$4"
  local docker_file_or_compose_sample_path="$5"
  local compose_project_name="$6"
  local revisado="$7"
  local dev_image="$8"
  local config_inifile="$9"

  local dockerfile_base_dev_sample
  local resposta
  local base_image

  local nome
  if [ "$tipo" = "dockerfile" ]; then
    nome="Dockerfile"
  else
    nome="docker-compose.yml"
  fi

  if [ ! -f ${env_file_path} ]; then
    echo_error "Arquivo $env_file_path não encontrado. Impossível continuar!"
    exit 1
  fi

  if [ ! -f "$docker_file_or_compose_sample_path" ]; then
    if [ "$LOGINFO" = "true" ]; then
      echo_warning "Arquivo $docker_file_or_compose_sample_path não encontrado."
    fi
  elif [ "$revisado" = "true" ]; then
    echo_warning "Arquivo $docker_file_or_compose_sample_path encontrado."
  fi

  if [ ! -f "$docker_file_or_compose_path" ]; then
    echo_warning "Arquivo $docker_file_or_compose_path não encontrado."
  fi

  if [ ! -f "$docker_file_or_compose_path" ] && [ -f "$docker_file_or_compose_sample_path" ]; then
    echo_warning "Detectamos que existe o arquivo $docker_file_or_compose_sample_path, porém não encontramos o arquivo $docker_file_or_compose_path."
    if [ "$tipo" = "dockerfile" ]; then
      echo_info "O arquivo '$docker_file_or_compose_path' contém instruções para construção de uma imagem Docker.
      Deseja copiar o arquivo de modelo $docker_file_or_compose_path para o arquivo definitivo $docker_file_or_compose_sample_path?"
    else
      echo_info "O arquivo \"$docker_file_or_compose_path\" é um arquivo de configuração usado pela ferramenta
      \"Docker Compose\" para definir e gerenciar múltiplos contêineres \"Docker\" como um serviço.
      Deseja copiar o arquivo de modelo $docker_file_or_compose_path para o arquivo definitivo ${docker_file_or_compose_sample_path}?"
    fi
    read -p "Pressione 'S' para confirmar ou [ENTER] para ignorar: " resposta
    resposta=$(echo "$resposta" | tr '[:lower:]' '[:upper:]')

    if [ "$resposta" = "S" ]; then
      if [ "$tipo" != "dockerfile" ]; then
        dockercompose_base=$(read_ini "$config_inifile" "dockercompose" "python_base" | tr -d '\r')
        project_dockercompose_base_sample_path="$(dirname $docker_file_or_compose_path)/${dockercompose_base}.sample"

        echo ">>> cp ${script_dir}/${dockercompose_base} $(dirname $docker_file_or_compose_path)/${dockercompose_base}"
        cp "${script_dir}/${dockercompose_base}" "$project_dockercompose_base_sample_path"
      fi
      echo ">>> cp $docker_file_or_compose_sample_path $docker_file_or_compose_path"
      cp "$docker_file_or_compose_sample_path" "$docker_file_or_compose_path"
    fi
  fi

  # Se $dev_image não foi definida OU não existe o arquivo Dockerfile, faça
  # gere um modelo Dockerfile sample e faça uma cópia para Dockerfile.
  if  [ ! -f "$docker_file_or_compose_path" ] || [ -z "$dev_image" ]; then
    if [ ! -f "$docker_file_or_compose_sample_path" ] || [ ! -f "$docker_file_or_compose_path" ]; then
      if [ -f "$docker_file_or_compose_path" ]; then
        echo_info "Detectamos que seu projeto já tem o arquivo \"$docker_file_or_compose_path\".
        Deseja que este script gere um arquivo modelo (${nome} sample) para seu projeto?"
      else
        echo_info "Deseja que este script gere um arquivo modelo (${nome} sample) para seu projeto?"
      fi
      read -p "Pressione 'S' para confirmar ou [ENTER] para ignorar: " resposta
      resposta=$(echo "$resposta" | tr '[:lower:]' '[:upper:]')
    fi

    if [ "$resposta" = "S" ] && [ ! -f "$docker_file_or_compose_sample_path" ] && [ -z "$dev_image" ]; then
      echo_error "A variável DEV_IMAGE não está definida no arquivo \"${env_file_path}\""
      echo_warning "Essa variável é usada pelo Dockerfile para definir a imagem base a ser utilizada para construir o contêiner."

      base_image=$(escolher_imagem_base)
      if [ "$base_image" != "default" ]; then
        dev_image=$(read_ini "$config_inifile" images "$base_image" | tr -d '\r')

        script_dir=$(dirname "$config_inifile")
        if [ "$tipo" = "dockerfile" ]; then
          filename=$(read_ini "$config_inifile" "dockerfile" "$base_image" | tr -d '\r')
          dockerfile_base_dev_sample="${script_dir}/dockerfiles/${filename}"
        else
          filename=$(read_ini "$config_inifile" "dockercompose" "$base_image" | tr -d '\r')
          dockerfile_base_dev_sample="${script_dir}/${filename}"
        fi

        echo "base_image: $base_image"
        echo "dev_image: $dev_image"
        echo "dockerfile_base_dev_sample: $dockerfile_base_dev_sample"

        if [ "$resposta" = "S" ]; then
          echo ">>> cp ${dockerfile_base_dev_sample} ${docker_file_or_compose_sample_path}"
          cp $dockerfile_base_dev_sample "${docker_file_or_compose_sample_path}"
          echo_success "Arquivo $docker_file_or_compose_sample_path criado!"
          sleep 0.5
        fi
      fi
    fi
  fi
  if  [ -z "$dev_image" ] && [ -f "$docker_file_path" ]; then
    # Extrair o valor de DEV_IMAGE usando o caminho definido em $docker_file_or_compose_path
    dev_image=$(grep -E "^ARG DEV_IMAGE=" "$docker_file_path" | cut -d '=' -f2)

    # Remover espaços em branco ao redor (caso haja)
    dev_image=$(echo "$dev_image" | xargs)
  fi

  # Testando a variável $dev_image novamente, pois ele pode ter sido definida no código acima.
  if [ -z "$dev_image" ]; then
    echo_error "A variável DEV_IMAGE não está definida no arquivo '${env_file_path}'"
    echo_info "Defina o valor dela em '${env_file_path}'"
    exit 1
  else
    if [ "$LOGINFO" = "true" ]; then
      echo_info "Variável de ambiente \"DEV_IMAGE=${dev_image}\" definida."
    fi

    # Extrair o valor de DEV_IMAGE do arquivo .env, definido em $env_file_path
    env_dev_image=$(grep -E "^DEV_IMAGE=" "$env_file_path" | cut -d '=' -f2)

    # Remover espaços em branco ao redor (caso haja)
    env_dev_image=$(echo "$env_dev_image" | xargs)

    # Atualiza o conteúdo da varíavel DEV_IMAGE no arquivo .env, se for diferente do conteúdo definido no Dockerfile
    if [ "$dev_image" != "$env_dev_image" ]; then
      dev_image="${dev_image:-base_image}"
      echo "--- Substituindo a linha 'DEV_IMAGE=' por 'DEV_IMAGE=${dev_image}' no arquivo $env_file_path"
      sed -i "s|^DEV_IMAGE=.*|DEV_IMAGE=${dev_image}|" "$env_file_path"
    fi
    if [ "$tipo" = "dockerfile" ]; then
      if [ -f "$docker_file_or_compose_path" ] && ! grep -q "${compose_project_name}-dev" "$docker_file_or_compose_path"; then
          echo "--- Substituindo \"app-dev\" por \"${compose_project_name}-dev\" no arquivo '${docker_file_or_compose_path}'"
          sed -i "s|app-dev|${compose_project_name}-dev|g" "$docker_file_or_compose_path"
      fi
    fi
  fi

  if [ ! -f "$docker_file_or_compose_path" ]; then
    projeto_dir_path=$(dirname $env_file_path)
    if [ "$tipo" = "dockerfile" ]; then
      mensagem_opcao="3. Se o arquivo $nome já existir, definir o path do arquivo na variável de ambiente \"DOCKERFILE\" no arquivo $env_file_path.
      Exemplo: DOCKERFILE=${projeto_dir_path}/$(basename $docker_file_or_compose_path)"
    else
      mensagem_opcao="3. Se o arquivo $nome já existir, definir o path do arquivo na variável de ambiente \"COMPOSES_FILES\" no arquivo $env_file_path.
Exemplo:
COMPOSES_FILES=\"
all:docker-compose.yml
\"
      "
    fi

    echo_error "Arquivo $docker_file_or_compose_path não encontrado. Impossível continuar!"
    echo_warning "O arquivo ${nome} faz parte da arquitetura do \"sdocker\".
    Há três formas para resolver isso:
    1. Gerar o arquivo \"$nome\". Para isso, execute novamente o \"sdocker\" (comando sdocker) e siga as orientações.
    2. Criar o arquivo $docker_file_or_compose_path no diretório raiz $projeto_dir_path do seu projeto.
    $mensagem_opcao"

    exit 1
  fi
}

if [ "$PROJECT_ROOT_DIR" != "$SCRIPT_DIR" ]; then
  verifica_e_configura_dockerfile_project "dockerfile" \
      "$PROJECT_ENV_PATH_FILE" \
      "$PROJECT_DOCKERFILE" \
      "$PROJECT_DOCKERFILE" \
      "$PROJECT_DOCKERFILE_SAMPLE" \
      "$COMPOSE_PROJECT_NAME" \
      "$REVISADO" \
      "$DEV_IMAGE" \
      "$INIFILE_PATH"

  verifica_e_configura_dockerfile_project "docker-compose" \
      "$PROJECT_ENV_PATH_FILE" \
      "$PROJECT_DOCKERFILE" \
      "$PROJECT_DOCKERCOMPOSE" \
      "$PROJECT_DOCKERCOMPOSE_SAMPLE" \
      "$COMPOSE_PROJECT_NAME" \
      "$REVISADO" \
      "$DEV_IMAGE" \
      "$INIFILE_PATH"

copy_docker_compose_base "$INIFILE_PATH" $PROJECT_DOCKERCOMPOSE

fi
##############################################################################
### INSERINDO VARIÁVEIS COM VALORES PADRÃO NO INICÍO DO ARQUIVO ENV
###############################################################################
# Só insere caso a variável não exista.

if [ "$PROJECT_ROOT_DIR" != "$SCRIPT_DIR" ] && [ "$TIPO_PROJECT" = "$PROJECT_DJANGO" ]; then
  insert_text_if_not_exists "DATABASE_DUMP_DIR=${DATABASE_DUMP_DIR}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "DATABASE_NAME=${DATABASE_NAME}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "VPN_GATEWAY_FAIXA_IP=${VPN_GATEWAY_FAIXA_IP}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "VPN_GATEWAY=${VPN_GATEWAY}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "USER_GID=${USER_GID}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "USER_UID=${USER_UID}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "USER_NAME=${USER_NAME}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "PGADMIN_EXTERNAL_PORT=${PGADMIN_EXTERNAL_PORT}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "REDIS_EXTERNAL_PORT=${REDIS_EXTERNAL_PORT}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "APP_PORT=${APP_PORT}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "REQUIREMENTS_FILE=${REQUIREMENTS_FILE}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "DOCKERFILE=${PROJECT_DOCKERFILE}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "POSTGRES_IMAGE=${POSTGRES_IMAGE}" "$PROJECT_ENV_PATH_FILE"
  #insert_text_if_not_exists "BASE_IMAGE=${BASE_IMAGE}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "DEV_IMAGE=${DEV_IMAGE}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "GIT_BRANCH_MAIN=${GIT_BRANCH_MAIN}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "WORK_DIR=${WORK_DIR}" "$PROJECT_ENV_PATH_FILE"
  insert_text_if_not_exists "COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}" "$PROJECT_ENV_PATH_FILE"
fi

##############################################################################
### TRATAMENTO DAS VARIÁVEIS DEFINDAS NO ARQUIVO ENV
##############################################################################

#echo "ARG_SERVICE = $ARG_SERVICE"
#echo "ARG_COMMAND = $ARG_COMMAND"
#echo "ARG_OPTIONS = $ARG_OPTIONS"
#echo "SERVICE_NAME = $SERVICE_NAME"
#echo "SERVICE_WEB_NAME = $SERVICE_WEB_NAME"
#echo "SERVICE_DB_NAME = $SERVICE_DB_NAME"
#echo "PROJECT_NAME = $PROJECT_NAME"
#echo "BASE_DIR = $BASE_DIR"
if [ "$PROJECT_ROOT_DIR" != "$SCRIPT_DIR" ] && [ "$REVISADO" = "false" ]; then
  imprime_variaveis_env $PROJECT_ENV_PATH_FILE
  echo_warning "Acima segue TODO os valores das variáveis definidas no arquivo \"${PROJECT_ENV_PATH_FILE}\"."
  echo "
  Segue abaixo as princípais variáveis:
    * Variável de configuração de caminho de arquivos:
        - BASE_DIR=${BASE_DIR}
        - DATABASE_DUMP_DIR=${DATABASE_DUMP_DIR}
        - REQUIREMENTS_FILE=${REQUIREMENTS_FILE} ${REQUIREMENTS_FILE_HELP}
        - WORK_DIR=${WORK_DIR} -- deve apontar para o diretório dentro do container onde está o código fonte da aplicação.

    * Variável de nomes de arquivos de configuração do Django:
        - SETTINGS_LOCAL_FILE_SAMPLE=${SETTINGS_LOCAL_FILE_SAMPLE}
        - SETTINGS_LOCAL_FILE=${SETTINGS_LOCAL_FILE}

    * Variável de configuração de banco:
        - DATABASE_NAME=${DATABASE_NAME}
        - DATABASE_USER=${DATABASE_USER}
        - DATABASE_PASSWORD=${DATABASE_PASSWORD}
        - DATABASE_HOST=${DATABASE_HOST}
        - DATABASE_PORT=${DATABASE_PORT}

    * Definições de portas para acesso externo ao containers, acesso à máquina host.
        - APP_PORT=${APP_PORT}
        - POSTGRES_EXTERNAL_PORT=${POSTGRES_EXTERNAL_PORT}
        - PGADMIN_EXTERNAL_PORT=${PGADMIN_EXTERNAL_PORT}
        - REDIS_EXTERNAL_PORT=${REDIS_EXTERNAL_PORT}

    * Definições de imagens
       - DEV_IMAGE=${DEV_IMAGE}
       - PYTHON_BASE_IMAGE=${PYTHON_BASE_IMAGE}
       - POSTGRES_IMAGE=${POSTGRES_IMAGE}

    * Configurações para criação de usuário no container web
       Este usuário isola as modificações dentro do container, evitando que alterações nas permissões dos arquivos
       do projeto afetem da máquina local host.
       - USER_NAME=${USER_NAME}
       - USER_UID=${USER_UID}
       - USER_GID=${USER_GID}

    * Configuração da rede interna
      - VPN_GATEWAY_FAIXA_IP=${VPN_GATEWAY_FAIXA_IP}
      - VPN_GATEWAY=${VPN_GATEWAY}

    * Demais varíaveis:
       - COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}
       - GIT_BRANCH_MAIN=${GIT_BRANCH_MAIN}
       - DOCKERFILE=${PROJECT_DOCKERFILE}

    * Variáveis par definição de acesso via VPN. [OPCIONAIS]
        - VPN_WORK_DIR=${VPN_WORK_DIR}  -- diretório onde estão os arquivos do container VPN
        Variáveis utilizadas para adicionar uma rota no container ${SERVICE_DB_NAME} para o container VPN
          - VPN_GATEWAY=${VPN_GATEWAY}
          - ROUTE_NETWORK=${ROUTE_NETWORK}
        - DOMAIN_NAME=${DOMAIN_NAME}
        - DATABASE_REMOTE_HOST=${DATABASE_REMOTE_HOST}
        Variáveis usadas para adiciona uma nova entrada no arquivo /etc/hosts no container DB,
        permitindo que o sistema resolva nomes de dominío para o endereço IP especificado.
          - ETC_HOSTS=${ETC_HOSTS} ${ETC_HOSTS_HELP}
  "
  echo_warning "Acima segue as principais variáveis definidas no arquivo \"${PROJECT_ENV_PATH_FILE}\"."
  echo_info "Antes de prosseguir, revise o conteúdo das variáveis apresentadas acima.
  Edite o arquivo \"$ENV_PATH_FILE\", copie e cole a definição \"REVISADO=true\" para está mensagem não mais ser exibida."
  echo "Tecle [ENTER] para continuar"
  read
  echo_info "Execute novamente o \"sdocker ${ARG_SERVICE} $ARG_COMMAND\"."
  exit 1
fi

if [ "$REVISADO" = "true" ]; then
  echo_info "Variável REVISADO=true"
fi

########################## Validações de variáveis definidas no arquivo .env  ##########################
if [ ! -d "$BASE_DIR" ]; then
  echo_error "Caminho do diretório \"$BASE_DIR\" definido na variável \"BASE_DIR\" no arquivo $PROJECT_ENV_PATH_FILE NÃO existe.
  Edite o arquivo e defina o caminho correto do diretório na variável"
  exit 1
fi

if [ ! -d "$DATABASE_DUMP_DIR" ]; then
  echo_error "Caminho do diretório \"$DATABASE_DUMP_DIR\" definido na variável \"DATABASE_DUMP_DIR\" no arquivo $PROJECT_ENV_PATH_FILE NÃO existe.
  Edite o arquivo e defina o caminho correto do diretório na variável"
  exit 1
fi

if [ "$USER_NAME" != $(id -un) ]; then
  echo_warning "Usuário \"$USER_NAME\" definido na variável \"USER_NAME\" no arquivo $PROJECT_ENV_PATH_FILE
  é diferente do usuário \"$(id -un)\" dos seu sistema operacional \"$(get_os_name)\"."

  echo_info "Deseja que este script faça as devidas correçõe no arquivo \"$PROJECT_ENV_PATH_FILE\" ?"
  read -p "Pressione 'S' para confirmar ou [ENTER] para ignorar: " resposta
  resposta=$(echo "$resposta" | tr '[:lower:]' '[:upper:]')  # Converter para maiúsculas
  if [ "$resposta" = "S" ]; then
    # Substitui os valores das variáveis com os novos valores dinâmicos
    sed -i "s/^USER_NAME=.*/USER_NAME=$(id -un)/" "$PROJECT_ENV_PATH_FILE"
    sed -i "s/^USER_UID=.*/USER_UID=$(id -u)/" "$PROJECT_ENV_PATH_FILE"
    sed -i "s/^USER_GID=.*/USER_GID=$(id -g)/" "$PROJECT_ENV_PATH_FILE"
    echo_success "Correções realizadas com suceso."
    echo "Tecle quaisquer tecla para continuar"
    read
  fi
fi

############ Tratamento para recuperar os arquivos docker-compose ############
function get_compose_command() {
  local project_env_path_file="$1"
  local project_dev_dir="$2"
  local dict_services_commands="$3"
  local dict_composes_files="$4"
  local config_inifile="$5"

  local dockercompose_base
  local composes_files=()
  local compose_filepath
  local dir_path

  local services=($(dict_keys "${dict_services_commands[*]}"))
  local project_env_dir="$(dirname $project_env_path_file)"

  if [ ! -f "$project_env_path_file" ]; then
    echo_error "Arquivo $project_env_path_file não encontrado. Impossível continuar!"
    exit 1
  fi

  for service in ${services[*]}; do
    local file=$(dict_get "$service" "${dict_composes_files[*]}")
    if [ ! -z "$file" ]; then
      compose_filepath="$file"
      dir_path="$(dirname $compose_filepath)"
      if [ "$dir_path" = "." ]; then
        compose_filepath=$project_env_dir/$file
      fi

      if [ ! -f "$compose_filepath" ]; then
        echo_error "Arquivo $compose_filepath não encontrado. Impossível continuar!"
        exit 1
      fi

      composes_files+=("-f $compose_filepath")
    fi
  done

  dockercompose_base=$(read_ini "$config_inifile" "dockercompose" "python_base" | tr -d '\r')
  # Verificar se o arquivo Dockerfile base existe no diretório onde estar o arquivo env.
  # Se não existir, verifica se existe no diretório root do projeto.
  compose_filepath="${project_env_dir}/${dockercompose_base}"
  if [ ! -f "$compose_filepath" ]; then
    compose_filepath="${project_dev_dir}/${dockercompose_base}"
    if [ ! -f "$compose_filepath" ]; then
#      echo "Arquivo $compose_filepath não existe"
#      return 0
      compose_filepath=""
    fi
  fi
  if [ ! -z "$compose_filepath" ]; then
    compose_filepath="-f $compose_filepath"
  fi

  # Retornar o valor de COMPOSE
  COMPOSE="docker compose ${compose_filepath} ${composes_files[*]}"
  echo "$COMPOSE"
  return 0
}

if [ "$PROJECT_ROOT_DIR" != "$SCRIPT_DIR" ]; then
  COMPOSE=$(get_compose_command "$PROJECT_ENV_PATH_FILE" \
      "$PROJECT_DEV_DIR" \
      "$DICT_SERVICES_COMMANDS" \
      "$DICT_COMPOSES_FILES" \
      "$INIFILE_PATH")

  _return_func=$?
  if [ $_return_func -eq 1 ]; then
    echo_error "$COMPOSE"
    exit 1
  fi
fi
########################## Validações das variávies para projetos DJANGO ##########################
sair=0
if [ "$PROJECT_ROOT_DIR" != "$SCRIPT_DIR" ] && [ "$TIPO_PROJECT" = "$PROJECT_DJANGO" ]; then

  # Verificar se a variável COMPOSE_PROJECT_NAME está definida
  if [ -z "${COMPOSE_PROJECT_NAME}" ]; then
      echo_error "A variável COMPOSE_PROJECT_NAME não está definida no arquivo \"${PROJECT_ENV_PATH_FILE}\""
      echo_info "Essa variável é usada pelo Docker Compose para definir o nome do projeto.
      O nome do projeto serve como um \"prefixo\" comum para os recursos criados por aquele projeto,
      como redes, volumes, containers e outros objetos Docker."
      echo_info "Sugestão de nome \"COMPOSE_PROJECT_NAME=PROJECT_NAME\". Copie e cole essa definição no arquivo \"${PROJECT_ENV_PATH_FILE}\""
      sair=1
  fi

  if [ ! -d "$BASE_DIR" ]; then
    echo_error "Diretório base do projeto $BASE_DIR não existe.!"
    echo_info "Defina o nome dele na variável \"BASE_DIR\" em \"${PROJECT_ENV_PATH_FILE}\""
    sair=1
  fi

  file_requirements_txt="${PROJECT_ROOT_DIR}/${REQUIREMENTS_FILE}"

  if [ ! -f "$file_requirements_txt" ]; then
    echo ""
    echo_error "Arquivo $file_requirements_txt não existe.!"
    echo_info "Esse arquivo possui as bibliotecas necessárias para a aplicação funcionar."
    echo_info "Defina o nome dele na variável \"REQUIREMENTS_FILE\" em \"${PROJECT_ENV_PATH_FILE}\""
    sair=1
  fi

  settings_local_file_sample=$SETTINGS_LOCAL_FILE_SAMPLE
  settings_local_file="${SETTINGS_LOCAL_FILE:-local_settings.py}"

  # Verifica se o arquivo local settings NÃO existe E se settings sample existe, confirmando,
  # copiara o arquivo settings sample para local settings confome nomes definidos
  # nas variáveis de ambiente acima
  if [ ! -f "$BASE_DIR/$settings_local_file" ] && [ -f "$BASE_DIR/$settings_local_file_sample" ]; then
    echo ">>> cp $BASE_DIR/$settings_local_file_sample $BASE_DIR/$settings_local_file"
    cp "$BASE_DIR/$settings_local_file_sample" "$BASE_DIR/$settings_local_file"
    sleep 0.5
  fi
  if [ ! -f "$BASE_DIR/$settings_local_file_sample" ]; then
    echo ""
    echo_error "Arquivo settings sample ($BASE_DIR/$settings_local_file_sample) não existe.!"
    echo_info "Esse arquivo é o modelo de configurações mínimas necessárias para a aplicação funcionar."
    echo_info "Defina o nome dele na variável \"SETTINGS_LOCAL_FILE_SAMPLE\" em \"${PROJECT_ENV_PATH_FILE}\""
    sair=1
  fi
  if [ ! -f "$BASE_DIR/$settings_local_file" ]; then
    echo ""
    echo_error "Arquivo $BASE_DIR/$settings_local_file não existe.!"
    echo_info "Esse arquivo possui as configurações mínimas necessárias para a aplicação funcionar."
    echo_info "Defina o nome dele na variável \"SETTINGS_LOCAL_FILE\" em \"${PROJECT_ENV_PATH_FILE}\""
    sair=1
  fi

  if [ $sair -eq 1 ]; then
    # Verifica se a variável existe no arquivo e possui valor
    if ! grep -q "^SETTINGS_LOCAL_FILE_SAMPLE=.*[^[:space:]]$" "$PROJECT_ENV_PATH_FILE"; then
      sair=1
      echo "Váriável \"SETTINGS_LOCAL_FILE_SAMPLE\" está vazia.
      Essa variável define o nome do arquivo modelo de configuração (settings) local.
      Em alguns projeto, o nome desse arquivo é \"local_settings_sample.py\".
      Edite o arquivo \"${PROJECT_ENV_PATH_FILE}\" e defina o valor para essa variável."
    fi
   # Verifica se a variável existe no arquivo e possui valor
    if ! grep -q "^SETTINGS_LOCAL_FILE=.*[^[:space:]]$" "$PROJECT_ENV_PATH_FILE"; then
      sair=1
      echo "Váriável \"SETTINGS_LOCAL_FILE\" está vazia.
      Essa variável define o nome do arquivo modelo de configuração (settings) local.
      Em alguns projeto, o nome desse arquivo é \"local_settings_sample.py\".
      Edite o arquivo \"${PROJECT_ENV_PATH_FILE}\" e defina o valor para essa variável."
    fi

    echo ""
    echo_error "Impossível continuar!"
    echo_error "Corriga os problemas relatados acima e então execute o comando novamente."
    exit $sair
  fi

  if [ ! -f "$SCRIPT_DIR/scripts/init_database.sh" ]; then
    echo_warning "Arquivo $SCRIPT_DIR/scripts/init_database.sh não existe. Sem ele, torna-se impossível realizar dump ou restore do banco.!"
    echo_warning "Tecle [ENTER] para continuar."
    read
  fi

  PRE_COMMIT_CONFIG_FILE="${PRE_COMMIT_CONFIG_FILE:-.pre-commit-config.yaml}"
  file_precommit_config="${PROJECT_DEV_DIR}/${PRE_COMMIT_CONFIG_FILE}"
  if [ ! -f "$file_precommit_config" ]; then
    echo ""
    echo_error "Arquivo $file_precommit_config não existe!"
    echo_info "O arquivo .pre-commit-config.yaml é a configuração central para o pre-commit, onde você define quais
    hooks serão executados antes dos commits no Git. Ele automatiza verificações e formatações, garantindo que o código
    esteja em conformidade com as regras definidas, melhorando a qualidade e consistência do projeto.

    Deseja que este script copie um arquivo pré-configurado para seu projeto?"
    read -p "Pressione 'S' para confirmar ou [ENTER] para ignorar: " resposta
    resposta=$(echo "$resposta" | tr '[:lower:]' '[:upper:]')  # Converter para maiúsculas
    if [ "$resposta" = "S" ]; then
      echo ">>> cp ${SCRIPT_DIR}/${PRE_COMMIT_CONFIG_FILE} $file_precommit_config"
      cp "${SCRIPT_DIR}/${PRE_COMMIT_CONFIG_FILE}" "$file_precommit_config"
      sleep 0.5

      if [ ! -d "${PROJECT_ROOT_DIR}/pre-commit-bin" ]; then
        echo ">>> mkdir -p ${PROJECT_ROOT_DIR}/pre-commit-bin"
        mkdir -p "${PROJECT_ROOT_DIR}/pre-commit-bin"
      fi
      sleep 0.5

      echo ">>> cp -r ${SCRIPT_DIR}/pre-commit-bin ${PROJECT_ROOT_DIR}/pre-commit-bin"
      cp -r "${SCRIPT_DIR}/pre-commit-bin" "${PROJECT_ROOT_DIR}"
      sleep 0.5
    fi
  fi
fi
##############################################################################
### Funções utilitárias para instanciar os serviços
##############################################################################

get_service_names() {
  # Função que retorna um array de nomes de serviços (excluindo "all")
  local _services=($(dict_keys "${DICT_SERVICES_COMMANDS[*]}"))
  local result=()

  for (( idx=${#_services[@]}-1 ; idx>=0 ; idx-- )); do
    local _name_service=${_services[$idx]}
    local _service_name_parse=$(dict_get $_name_service "${DICT_ARG_SERVICE_PARSE[*]}")

    for _parsed_service in ${_service_name_parse[*]}; do
      _name_service=$_parsed_service
    done

    # Adicionar ao array apenas se o nome do serviço não for "all"
    if [ "$_name_service" != "all" ]; then
      result+=("$_name_service")
    fi
  done

  echo "${result[@]}"  # Retorna o array de nomes
}

# Função para verificar a validade do comando
function check_command_validity() {
  local command=$1
  local available_commands=("$2")
  local all_commands_local=("$3")
  local arg_count=$4
  local message=$5

  # As variáveis de erro são passadas por referência
  local -n error_danger_message=$6
  local -n error_warning_message=$7

  local service_name="$8"

  if ! in_array "$command" "${available_commands[*]}" && ! in_array "$command" "${all_commands_local[*]}"; then
    error_danger_message="${message} [${command}] não existe."
    if [ ! -z "$service_name" ]; then
      error_danger_message="${message} [${command}] não existe para o serviço [${service_name}]."
    fi

    error_warning_message="${message}s disponíveis: ${available_commands[*]}"

    if [ ! -z "$all_commands_local" ]; then
      error_warning_message="${message}s disponíveis: \n\t\tcomuns: ${all_commands_local[*]} \n\t\tespecíficos: ${available_commands[*]}"
    fi
    return 1 # falha - serviço não existe
  else
    return 0 # sucesso - serviço existe
  fi
  return 0 # Sucesso, comando válido
}

# Função para verificar e validar argumentos
function verify_arguments() {
  # Copia os argumentos para um array local
  local arg_service_name=$1
  local arg_command=$2
  local services_local=("$3")
  local specific_commands_local=("$4")
  local all_commands_local=("$5")
  local arg_count=$6

  # As variáveis de erro são passadas por referência
  local -n error_message_danger=$7
  local -n error_message_warning=$8

  declare -a empty_array=()

  if [ $arg_count -eq 0 ]; then
    error_message_danger="Argumento [NOME_SERVICO] não informado."
    error_message_warning="Serviços disponíveis: ${services_local[@]}"
    return 1 # falha
  fi

  # Verifica se o serviço existe
  check_command_validity "$arg_service_name" "${services_local[*]}" "${empty_array[*]}" "$arg_count" "Serviço" error_message_danger error_message_warning
  local _service_ok=$?
  if [ $_service_ok -eq 1 ]; then
    return 1
  fi

  if [ $arg_count -eq 1 ]; then
    if [ $_service_ok -eq 0 ]; then # serviço existe
      error_message_danger="Argumento [COMANDOS] não informado."
      error_message_warning="Service $arg_service_name
          Comandos disponíveis:
              Comuns: ${all_commands_local[*]}
              Específicos: ${specific_commands_local[*]}"
      if [ "$arg_service_name" = "web" ]; then
        error_message_warning="${error_message_warning}
              o comando \"up\" possui os argumentos \"--force-deploy-all\" e \"--force-deploy-dev\":
              --force-deploy-all: força a construção (build) de todas os estágios de imagens.
              --force-deploy-dev: força a construção (build) apenas do estágio da imagem dev, arquivo Dockerfile.
              Exemplo de uso: sdocker web up --force-deploy-all"
      fi
    fi
    return 1 # falha
  fi

  # Verifica se o comando para o serviço existe.
  check_command_validity "$arg_command" "${specific_commands_local[*]}" "${all_commands_local[*]}" "$arg_count" "Comando" error_message_danger error_message_warning "$arg_service_name"
  local _command_ok=$?
  if [ $_command_ok -eq 1 ]; then
    return 1
  fi
  return 0 #sucesso
}

function imprimir_orientacao_uso() {
  local __usage="
  Usar: $CURRENT_FILE_NAME [NOME_SERVICO] [COMANDOS] [OPCOES]
  Nome do serviço:
    all                         Representa todos os serviços
    web                         Serviço rodando a aplicação WEB
    db                          Serviço rodando o banco PostgreSQL
    pgadmin                     [Só é iniciado sob demanda]. Deve ser iniciado após o *db* , usar o endereço http://localhost:${PGADMIN_EXTERNAL_PORT} , usuário **admin@pgadmin.org** , senha **admin** .
    redis                       Serviço rodando o cache Redis
    celery                      [Só é iniciado sob demanda]. Serviço rodando a aplicacão SUAP ativando a fila de tarefa assíncrona gerenciada pelo Celery

  Comandos:

    Comando comuns: Comandos comuns a todos os serciços, exceto **all**
      up                        Sobe o serviço [NOME_SERVICO] em **foreground**
                                Este comando possui os argumentos force-deploy-all e force-deploy-dev:
                                - force-deploy-all: força a construção (build) de todas os estágios de imagens.
                                - force-deploy-dev: força a construção (build) apenas do estágio da imagem dev, arquivo Dockerfile.
      down                      Para o serviço [NOME_SERVICO]
      restart                   Para e reinicar o serviço [NOME_SERVICO] em **background**
      exec                      Executar um comando usando o serviço [NOME_SERVICO] já subido antes, caso não tenha um container em execução, o comando é executado em em um novo container
      run                       Executa um comando usando a imagem do serviço [NOME_SERVICO] em um **novo** serviço
      logs                      Exibe o log do serviço [NOME_SERVICO]
      shell                     Inicia o shell (bash) do serviço [NOME_SERVICO]

    Comandos específicos:

      all:
        deploy                  Implanta os serviços, deve ser executado no primeiro uso, logo após o
        undeploy                Para tudo e apaga o banco, útil para quando você quer fazer um reset no ambiente
        redeploy                Faz um **undeploy** e um **deploy**
        status                  Lista o status dos serviços
        restart                 Reinicia todos os serviços em ****background***
        logs                    Mostra o log de todos os serviços
        up                      Sobe todos os serviços em **foreground**
        down                    Para todos os serviços

      web:
        build                Constrói a imagem da aplicação web
        makemigrations       Executa o **manage.py makemigrations**
        manage               Executa o **manage.py**
        migrate              Executa o **manage.py migrate**
        shell_plus           Executa o **manage.py shell_plus**
        debug                Inicia um serviço com a capacidade de usar o **breakpoint()** para **debug**

      db:
        psql                 Executa o comando **psql** no serviço
        wait                 Prende o console até que o banco suba, útil para evitar executar **migrate** antes que o banco tenha subido completamente
        dump               Realiza o dump do banco no arquivo $DIR_DUMP/$POSTGRES_DB.sql.gz
        restore              Restaura o banco do arquivo *.sql ou *.gz que esteja no diretório $DIR_DUMP

  Opções: faz uso das opções disponíveis para cada [COMANDOS]

  ˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆ
  "
  echo_info "$__usage"
}

# Função para imprimir erros
function print_error_messages() {
  local error_danger_message=$1
  local error_info_message=$2

  if [ ! -z "$error_info_message" ]; then
    imprimir_orientacao_uso
    echo_error "$error_danger_message"
    echo_warning "$error_info_message

    Usar: $CURRENT_FILE_NAME [NOME_SERVICO] [COMANDOS] [OPCOES]
    Role para cima para demais detalhes dos argumentos [NOME_SERVICO] [COMANDOS] [OPCOES]
    "
    exit 1
  fi
}

# Função para processar o comando com base no serviço e argumentos
function process_command() {
  local arg_count=$1
  local service_exists=$2
  _service_name=$(get_server_name "${ARG_SERVICE}")

  if [ "$ARG_COMMAND" = "up" ]; then
    service_up "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "down" ]; then
    service_down "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "restart" ]; then
    service_restart "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "exec" ]; then
    service_exec "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "run" ]; then
    service_run "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "logs" ]; then
    service_logs "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "shell" ]; then
    service_shell "${_service_name}" "$ARG_OPTIONS"

  #for all containers
  elif [ "$ARG_COMMAND" = "status" ]; then
    service_status "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "undeploy" ]; then
    service_undeploy "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "deploy" ]; then
    service_deploy "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "redeploy" ]; then
    service_redeploy "${_service_name}" "$ARG_OPTIONS"

  #for db containers
  elif [ "$ARG_COMMAND" = "psql" ]; then
    command_db_psql "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "restore" ]; then
    database_db_restore "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "dump" ]; then
    database_db_dump "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "copy" ]; then
    database_db_scp "${_service_name}" "$ARG_OPTIONS"

  #for web containers
  elif [ "$ARG_COMMAND" = "build" ]; then
    service_build "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "manage" ]; then
    command_web_django_manage "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "makemigrations" ]; then
    command_web_django_manage "${_service_name}" makemigrations "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "migrate" ]; then
    command_web_django_manage  "${_service_name}" "migrate" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "shell_plus" ]; then
    command_web_django_manage "${_service_name}" "shell_plus" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "test_behave" ]; then
    command_web_test_behave  "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "debug" ]; then
    command_web_django_debug "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "pre-commit" ]; then
    command_pre_commit "${_service_name}" "$ARG_OPTIONS"
  elif [ "$ARG_COMMAND" = "git" ]; then
    command_git "${_service_name}" "$ARG_OPTIONS"
  else
    echo_warning "Comando $ARG_COMMAND sem função associada"

    declare -a available_commands
    list_keys_in_section "$INIFILE_PATH" "extensions" available_commands

    for command in "${available_commands[@]}"; do
      script_path=$(get_filename_path "$PROJECT_DEV_DIR" "$INIFILE_PATH" "extensions" "$command")
      # Verifica e remove ocorrências de "//"
      script_path=$(echo "$script_path" | sed 's#//*#/#g')

      arg_command=${ARG_COMMAND//-/_}
      "${SCRIPT_DIR}/${script_path}" "$arg_command" $ARG_OPTIONS
    done
  fi
}

##############################################################################
### FUNÇÕES RESPONSÁVEIS POR INSTACIAR OS SERVIÇOS
##############################################################################
function docker_build() {
  local scripty_dir="$1"
  local inifile_path="$2"
  local chave_ini="$3"
  local image_from="$4"
  local work_dir="$5"
  local requirements_file="$6"
  local user_name="$7"
  local user_uid="$8"
  local user_gid="$9"
  local force="${10}"

  dockerfile=$(get_filename_path "${scripty_dir}" "$inifile_path" "dockerfile" "$chave_ini")

  # Substitui "_" por "-"
  image="${chave_ini//_/-}"

  if [ "$force" = true ] || ! verifica_imagem_docker "$image" "latest" ; then
    echo ">>>
    docker build
      --build-arg WORK_DIR=$work_dir
      --build-arg REQUIREMENTS_FILE=$requirements_file
      --build-arg USER_UID=$user_uid
      --build-arg USER_GID=$user_gid
      --build-arg USER_NAME=$user_name
      -t $image
      -f ${scripty_dir}/dockerfiles/${dockerfile} .
    "
    docker build \
      --build-arg WORK_DIR="$work_dir" \
      --build-arg REQUIREMENTS_FILE="$requirements_file" \
      --build-arg USER_UID="$user_uid" \
      --build-arg USER_GID="$user_gid" \
      --build-arg USER_NAME="$user_name" \
      -t "$image" \
      -f "${scripty_dir}/dockerfiles/${dockerfile}" .
    _return_command=$?
    if [ "$_return_command" -ne 0 ]; then
      echo_error "Falha a compilar a imagem \"$image\", veja o erro acima."
      exit 1
    fi
  elif verifica_imagem_docker "$image" "latest"; then
      echo_warning "A imagem ${image}:latest já existe localmente.
      Caso queria reconstruí-la novamente, use a opção \"--force\"."
  fi
}

function build_python_base() {
  local force="$1"
  echo ">>> ${FUNCNAME[0]} $force"

  docker_build "$SCRIPT_DIR" \
    "$INIFILE_PATH" \
    "python_base" \
    "${PYTHON_BASE_IMAGE:-python:3.12-slim-bullseye}" \
    "" \
    "" \
    "" \
    "" \
    "" \
    $force
}

function build_python_base_user() {
  local force="$1"
  echo ">>> ${FUNCNAME[0]} $force"
  docker_build "$SCRIPT_DIR" \
  "$INIFILE_PATH" \
  "python_base_user" \
  "${PYTHON_BASE_USER_IMAGE:-python-base:latest}" \
  "" \
  "" \
  $USER_NAME \
  $USER_UID \
  $USER_GID \
  $force
}

function build_python_nodejs_base() {
  local force="$1"
  echo ">>> ${FUNCNAME[0]} $force"
  docker_build "$SCRIPT_DIR" \
    "$INIFILE_PATH" \
    "python_nodejs_base" \
    "${PYTHON_NODEJS_BASE_IMAGE:-python-base-user:latest}" \
    "" \
    "" \
    "" \
    "" \
    "" \
    "$force"
}

function docker_build_all() {
  local option=$1
  echo ">>> ${FUNCNAME[0]} $option"

  local force=false
  if echo "$_option" | grep -q -- "--force"; then
    force=true
  fi

  build_python_base $force
  build_python_base_user $force
  build_python_nodejs_base $force

#  if [ "$force" = "false" ]; then
#    echo "Tecle [ENTER] para continuar"
#    read
#  fi
}

#function check_option_d() {
#  local _option="$1"
#
#  if expr "$_option" : '.*-d' > /dev/null; then
#    return 0  # Verdadeiro (True)
#  else
#    return 1  # Falso (False)
#  fi
#}

function is_container_running() {
  local _service_name="$1"
#  echo ">>> ${FUNCNAME[0]} $_service_name"

  # Verifica se o container está rodando
  if ! $COMPOSE ps | grep -q "${_service_name}.*Up"; then
    echo_warning "O container \"$_service_name\" não está inicializado."
    return 1
  fi
  return 0
  # usar:
  # if ! is_container_running "$_service_name"; then
  # ...
  # fi
}

function container_failed_to_initialize() {
  local exit_code=$?
  local error_message="$1"
  local _service_name="$2"
  local _option="${*:3}"
  local erro_resolvido=false

  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  if [ $exit_code -ne 0 ] || echo "$error_message" | grep -iq "error"; then
      # Exibe a mensagem de erro e interrompe a execução do script
      echo_error "Falha ao inicializar o container.
      $error_message"
#      if echo "$error_message" | grep -iq "Address already in use"; then
#      fi

      if echo "$error_message" | grep -iq "port is already allocated"; then
          # Verifica qual container está usando a porta 5432
          # docker inspect -f '{{.Name}} - {{.NetworkSettings.Ports}}' $(docker ps -q) | grep -q 5432

          local port
          # Utilizando expressão regular para capturar a porta
          port=$(echo "$error_message" | grep -oP '0\.0\.0\.0:\K[0-9]+')

          # Obter o serviço que está usando a porta especificada
          local service
          service=$(docker ps --filter "publish=${port}" --format "{{.Names}}")

          echo_warning "
          O erro que ocorreu indica que a porta $port já está em uso no sistema, e o Docker não conseguiu
          vincular outra instância do serviço a essa mesma porta.
          Para resolver o problema, existem algumas opções:
          1. Definir uma nova porta para o serviço \"$_service_name\" no arquivo \".env\".
          2. Verificar qual processo/serviço está utilizando a porta e parar o processo em execução.
          "
          if [ ! -z "$service" ]; then
            echo_info "Foi detectado que o serviço \"$service\" está utilizando a porta \"$port\".
            Deseja encerrar a execução desse serviço?"

            read -p "Pressione 'S' para confirmar ou [ENTER] para ignorar: " resposta
            resposta=$(echo "$resposta" | tr '[:lower:]' '[:upper:]')  # Converter para maiúsculas
            if [ "$resposta" = "S" ]; then
              echo ">>> docker stop $service"
              docker stop "$service"
              erro_resolvido=true
            fi
          fi
      fi
#      echo_warning "Parando todos os serviços dependentes de \"$_service_name\" que estão em execução ..."
#      declare -a _name_services
#      dict_get_and_convert "$_service_name" "${DICT_SERVICES_DEPENDENCIES[*]}" _name_services
#
#      for _nservice in "${_name_services[@]}"; do
#        service_stop "$_nservice" $_option
#      done
      if [ "$erro_resolvido" = false ]; then
        service_stop "$_service_name" $_option
        exit 1 # falha ocorrida
      fi
  fi
}

function service_run() {
  local _service_name="$1"
  shift # Remover o primeiro argumento posicional ($1) -- Remove o nome do serviço da lista de argumentos
  local _option="$@"
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  if [ "$_service_name" = "$SERVICE_WEB_NAME" ]; then
    echo ">>> $COMPOSE run --rm -w $WORK_DIR -u jailton $_service_name $_option"
    $COMPOSE run --rm -w $WORK_DIR -u $USER_NAME "$_service_name" $_option
  else
    echo ">>> $COMPOSE run $_service_name $_option"
    $COMPOSE run --rm "$_service_name" $_option
  fi
}

function service_web_exec() {
  local _option="${@:2}"
  local _service_name=$1
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  if [ "$(docker container ls | grep ${COMPOSE_PROJECT_NAME}-${_service_name}-1)" ]; then
    echo ">>> $COMPOSE exec $_service_name $_option"
    $COMPOSE exec "$_service_name" $_option
  else
    echo_warning "O serviço $_service_name não está em execução"
  fi
}

function _service_exec() {
  local _service_name="$1"
  shift # Remover o primeiro argumento posicional ($1) -- Remove o nome do serviço da lista de argumentos
  local _option="$@"
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

#  if [ "$(docker container ls | grep "${COMPOSE_PROJECT_NAME}-${_service_name}-1")" ]; then
  if docker container ls | grep -q "${COMPOSE_PROJECT_NAME}-${_service_name}-1"; then
    if [ "$ARG_SERVICE" = "pgadmin" ]; then
      _option=$(echo $_option | sed 's/bash/\/bin\/sh/')
    fi
    echo ">>> $COMPOSE exec $_service_name $_option"
    $COMPOSE exec "$_service_name" $_option
  else
    service_run "$_service_name" $_option
  fi
}

function service_exec() {
  local _service_name="$1"
  shift # Remover o primeiro argumento posicional ($1) -- Remove o nome do serviço da lista de argumentos
  local _option="$@"
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  if [ "$ARG_SERVICE" = "$SERVICE_WEB_NAME" ]; then
    service_web_exec "$_service_name" $_option
  else
    _service_exec "$_service_name" $_option
  fi
}

function service_shell() {
  local _option="${@:2}"
  local _service_name=$1
  echo ">>> ${FUNCNAME[0]} "$_service_name" $_option"

  if ! is_container_running "$_service_name"; then
    echo_warning "Container $_service_name não está em execução!"
  fi

  if docker container ls | grep -q "${COMPOSE_PROJECT_NAME}-${_service_name}-1"; then
    service_exec "$_service_name" bash $_option
  else
    service_run "$_service_name" bash $_option
  fi

  #OCI runtime exec failed: exec failed: container_linux.go:380: starting container process caused: exec: "bash": executable file not found in $PATH: unknown
}

function service_logs() {
  local _option="${@:2}"
  local _service_name=$1
  echo ">>> ${FUNCNAME[0]} "$_service_name" $_option"

  if [ "$_service_name" = "all" ]; then
    echo_info "Status dos serviços"
    $COMPOSE logs -f $_option
  else
    if ! is_container_running "$_service_name"; then
      echo_warning "Container $_service_name não está em execução!"
    fi
    $COMPOSE logs -f $_option "$_service_name"
  fi
}

function service_stop() {
  local _option="${@:2}"
  local _service_name=$1
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  # Para o segundo caso com _service_name
  declare -a _name_services
  dict_get_and_convert "$_service_name" "${DICT_SERVICES_DEPENDENCIES[*]}" _name_services

  for _nservice in "${_name_services[@]}"; do
    if docker container ls | grep -q "${COMPOSE_PROJECT_NAME}-${_nservice}-1"; then
      echo ">>> docker stop ${COMPOSE_PROJECT_NAME}-${_nservice}-1"
      docker stop ${COMPOSE_PROJECT_NAME}-${_nservice}-1
    fi
  done
  if docker container ls | grep -q "${COMPOSE_PROJECT_NAME}-${_service_name}-1"; then
    echo ">>> docker stop ${COMPOSE_PROJECT_NAME}-${_service_name}-1"
    docker stop ${COMPOSE_PROJECT_NAME}-${_service_name}-1
  fi
}

function compose_service_db_get_host_port() {
  local return_func

  # Executa o comando dentro do contêiner
  psql_output=$($COMPOSE exec -T "$SERVICE_DB_NAME" bash -c "
  export POSTGRES_USER='$POSTGRES_USER' &&
  export POSTGRES_HOST='$POSTGRES_HOST' &&
  export POSTGRES_PORT='$POSTGRES_PORT' &&
  export POSTGRES_PASSWORD='$POSTGRES_PASSWORD' &&
  source /scripts/utils.sh && get_host_port '\$POSTGRES_USER' '\$POSTGRES_HOST' '\$POSTGRES_PORT' '\%POSTGRES_PASSWORD' ")

  return_func=$?
  echo "$psql_output"
  return $return_func
}

function compose_db_check_exists() {
  local host
  local port
  local return_func

  # Chamar a função para obter o host e a porta correta
  psql_output=$(compose_service_db_get_host_port)
  _return_func=$?
  if [ $_return_func -eq 0 ]; then
    read host port <<< $psql_output
  else
    echo_error "Não foi possível conectar ao banco de dados."
    exit 1
  fi

  # Executa o comando dentro do contêiner
  $COMPOSE exec -T "$SERVICE_DB_NAME" bash -c "
  source /scripts/utils.sh && check_db_exists $POSTGRES_USER $host $port $POSTGRES_PASSWORD $POSTGRES_DB"
  return_func=$?
  return $return_func
}

function django_migrations_exists() {
  local host
  local port
  local return_func

  psql_output=$(compose_service_db_get_host_port)
  _return_func=$?

  psql_output=$(echo "$psql_output" | xargs)  # remove espaços

  # Se a função retornar com sucesso (_return_func igual a 1)
  if [ $_return_func -eq 0 ]; then
    # Extrai o host e a porta do output
    read -r host port <<< "$psql_output"
  fi

  local _psql="psql -h $host -p $port -U $POSTGRES_USER -d $POSTGRES_DB"

  # Definindo o comando psql para verificar a presença de migrações
  local psql_cmd="$_psql -tc 'SELECT COUNT(*) > 0 FROM django_migrations;'"

  psql_output=$($COMPOSE exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$SERVICE_DB_NAME" sh -c "$psql_cmd")
  return_func=$?
  echo "$psql_output"
  return $return_func
}

function service_db_wait() {
  local _service_name=$SERVICE_DB_NAME
  local host
  local port

  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  echo "--- Aguardando conexão com o servidor de banco de dados ..."

  # Define por padrão o retorno como falha
  _return_func=1

  # Loop until para continuar tentando até que _return_func seja igual a 1
  until [ $_return_func -eq 0 ]; do
    echo_warning "Tentando conectar ao servidor de banco de dados, Aguarde!
    Caso deseje monitorar o log do servidor de banco de dados,
    abra um novo terminal e execute 'sdocker db logs'."
    psql_output=$(compose_service_db_get_host_port)
    _return_func=$?

    # Se a função retornar com sucesso (_return_func igual a 1)
    if [ $_return_func -eq 0 ]; then
      # Extrai o host e a porta do output
      read -r host port <<< "$psql_output"
    fi
    # Pequena pausa antes de tentar novamente
    sleep 2
  done
  echo_success "Servidor de banco de dados está aceitando conexões."

#  psql_command="psql -v ON_ERROR_STOP=1 --host=$host --port=$port --username=$POSTGRES_USER --dbname=$POSTGRES_DB"
#
#  echo ">>> [LOOP] $COMPOSE exec -T $SERVICE_DB_NAME bash -c \"PGPASSWORD=******* $psql_command -tc 'SELECT 1;'\" 2>&1"
#  until sql_output=$($COMPOSE exec -T "$SERVICE_DB_NAME" bash -c "PGPASSWORD=$POSTGRES_PASSWORD $psql_command -tc 'SELECT 1;'" 2>&1); do
#    psql_output=$(echo "$psql_output" | xargs)  # remove espaços
#    echo "ERROR: $psql_output"
#    echo_warning "Banco de dados está não disponível - aguardando... "
#    sleep 2
#  done
#
#  echo_success "Banco de dados está pronto e aceitando conexões."
}

function database_wait() {
  local _service_name=$SERVICE_DB_NAME
  echo ">>> ${FUNCNAME[0]} "$_service_name" $_option"

  service_db_wait

  echo ""
  echo "--- Verificando se o banco de dados \"$POSTGRES_DB\" existe ..."

  if ! compose_db_check_exists; then
    echo ""
    echo_warning "Banco \"$POSTGRES_DB\" não existe."
    echo "Deseja iniciar a restauração do dump agora?"
    read -p "Pressione 'S' para confirmar ou [ENTER] para ignorar: " resposta
    resposta=$(echo "$resposta" | tr '[:lower:]' '[:upper:]')  # Converter para maiúsculas

    if [ "$resposta" = "S" ]; then
      database_db_restore "$SERVICE_DB_NAME"
    else
      echo_error "Impossível continuar, banco \"$POSTGRES_DB\" não encontrado.
      Execute o comando \"sdocker db restore\" para restaurar o dump do banco.
      Certifique que o arquivo de dump existe na pasta \"[root_projeto]\dump\""
      exit 1
    fi
  else
    echo_success "Banco de dados \"$POSTGRES_DB\" encontrado!"
  fi

  echo ""
  echo "--- Verificando se a tabela \"django_migrations\" existe no banco \"$POSTGRES_DB\" ..."
  psql_output=$(django_migrations_exists)
  _return_func=$?
  if [ $_return_func -eq 1 ]; then
    echo ""
    echo_warning "Banco \"$POSTGRES_DB\" existe, porém tabela \"django_migrations\" não existe!"
    echo "Deseja iniciar a restauração do dump agora?"
    read -p "Pressione 'S' para confirmar ou [ENTER] para ignorar: " resposta
    resposta=$(echo "$resposta" | tr '[:lower:]' '[:upper:]')  # Converter para maiúsculas

    if [ "$resposta" = "S" ]; then
      database_db_restore "$SERVICE_DB_NAME"
      has_restore=$?
      # Verifica se o código de saída do comando anterior foi executado com falha
      if [ $has_restore -ne 0 ]; then
        exit 1
      fi

    else
      echo_error "Impossível continuar, banco \"$POSTGRES_DB\" continua vazio.
      Execute o comando \"sdocker db restore\" para restaurar o dump do banco.
      Certifique que o arquivo de dump existe na pasta \"[root_projeto]\dump\""
      exit 1
    fi
  else
    echo_success "Tabela \"django_migrations\" identificada!"
  fi

  echo ""
  echo "--- Aguardando banco de dados \"$POSTGRES_DB\" ficar pronto ..."

  psql_output=$(django_migrations_exists)
  _return_func=$?
  until [ $_return_func -eq 0 ]; do
    echo_warning "O banco \"$POSTGRES_DB\" ainda não está pronto, Aguarde... "
    psql_output=$(django_migrations_exists)
    _return_func=$?
    if [ $_return_func -eq 1 ]; then
      echo "Detalhes do erro: $psql_output"
    fi
    sleep 5
  done
  echo_success "Banco de dados \"$POSTGRES_DB\" está pronto para uso."
}

function database_db_scp() {
  local _option="${@:2}"
  local _service_name=$SERVICE_DB_NAME

  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  if ! is_container_running "$_service_name"; then
    echo_info "Inicializando o container $_service_name automaticamente ..."
    echo ">>> service_up $_service_name $_option -d"
    service_up $_service_name $_option -d
    sleep 1
  fi

  service_db_wait

  # > /dev/null: redireciona apenas a saída padrão (stdout) para /dev/null, descartando todas as
  # saídas normais, mas permitindo que os erros (stderr) ainda sejam exibidos.

  echo "$COMPOSE exec $_service_name sh -c \"
    apt-get update > /dev/null && apt-get install -y openssh-client > /dev/null
    scp -i /tmp/dbuser.pem dbuser@$DOMAIN_NAME:/var/opt/backups/$DATABASE_REMOTE_HOST.tar.gz /dump/$DATABASE_REMOTE_HOST.tar.gz
    \""
  $COMPOSE exec $_service_name sh -c "
    apt-get update > /dev/null && apt-get install -y openssh-client > /dev/null
    scp -i /tmp/dbuser.pem dbuser@$DOMAIN_NAME:/var/opt/backups/$DATABASE_REMOTE_HOST.tar.gz /dump/$DATABASE_REMOTE_HOST.tar.gz
    "

}

function database_db_dump() {
  local _option="$@"
  local _service_name=$SERVICE_DB_NAME
  echo ">>> ${FUNCNAME[0]} "$_service_name" $_option"

  echo "--- Realizando o dump do banco $POSTGRES_DB ... "

  _psql="psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER"

  # Definindo a consulta para pegar o tamanho do banco de dados
  psql_cmd="$_psql -d postgres -tc \"SELECT pg_database_size('$POSTGRES_DB');\""

  # Executando o comando dentro do container Docker para obter o tamanho do banco de dados
  result=$($COMPOSE exec -e PGPASSWORD=$POSTGRES_PASSWORD $_service_name sh -c "$psql_cmd")

  # Verificando se a variável result contém um valor válido
  result=$(echo $result | xargs)  # Remove espaços extras

  # Definir o comando pg_dump com pv e gzip
  pg_dump_cmd="pg_dump -U $POSTGRES_USER -h $POSTGRES_HOST -p $POSTGRES_PORT $POSTGRES_DB | \
  pv -c -s $result -N dump | \
  gzip > /dump/$POSTGRES_DB.sql.gz"

  if is_container_running "$_service_name"; then
    echo ">>> Executando: $COMPOSE exec -e PGPASSWORD=$POSTGRES_PASSWORD $_service_name sh -c \"$pg_dump_cmd\""
    $COMPOSE exec -e PGPASSWORD="$POSTGRES_PASSWORD" $_service_name sh -c "
    apt-get update && apt-get install -y pv gzip &&
    $pg_dump_cmd"
  else
    $COMPOSE run --rm --no-deps -e PGPASSWORD="$POSTGRES_PASSWORD" $_service_name sh -c "
    apt-get update && apt-get install -y pv gzip &&
    $pg_dump_cmd"
  fi

  echo ">>> service_exec $_service_name chmod 644 /dump/$POSTGRES_DB.sql.gz"
  service_exec "$_service_name" chmod 644 /dump/$POSTGRES_DB.sql.gz

  # Verifica se o código de saída do comando anterior foi executado com falha
  if [ $? -ne 0 ]; then
    echo_warning "Falha ao restaurar dump do banco $POSTGRES_DB"
  else
    echo_info "Backup realizado com sucesso!"
  fi
}

function database_db_restore() {
  local _service_name=$SERVICE_DB_NAME
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  if ! is_container_running "$_service_name"; then
    echo_info "Inicializando o container db automaticamente ..."
    echo ">>> service_up $_service_name $_option -d"
    service_up $_service_name $_option -d
  fi

  service_db_wait

  service_exec "$_service_name" touch /dump/restore.log
  service_exec "$_service_name" chmod 777 /dump/restore.log

  mkdir -p $DIR_DUMP

  local _falha=1
  local _retorno_func=0
  echo "--- Iniciando processo de restauração do dump ..."

  service_exec "$_service_name" /docker-entrypoint-initdb.d/init_database.sh

  # Verifica o código de saída do comando anterior foi executado com sucesso
  _retorno_func=$?
  echo "Código de retorno:  $_retorno_func"
  if [ "$_retorno_func" -eq 0 ]; then
    _falha=0
    echo_success "A restauração foi realizada com sucesso!"
    echo ""
    echo "Deseja visualizar o arquivo de log gerado?"
    read -p "Pressione 'S' para confirmar ou [ENTER] para ignorar: " resposta
    resposta=$(echo "$resposta" | tr '[:lower:]' '[:upper:]')  # Converter para maiúsculas

    if [ "$resposta" = "S" ]; then
      cat "$DIR_DUMP/restore.log"
    fi
  else
    #$PROJECT_DEV_DIR/scripts/init_database.sh
    echo_error "Impossível restauarar o dump. Veja os erros acima."
  fi
  return $_falha
}

function _service_db_up() {
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"
  local _service_name=$1
  local _option="${@:2}"

  local psql

  if docker container ls | grep -q "${COMPOSE_PROJECT_NAME}-${_service_name}-1"; then
    echo_warning "O container Postgres já está em execução."
#    echo_info "Deseja abrir o log para monitorar a execução?.
#    Para sair do log, digite as teclas Ctrl + C
#    Você também pode executar manualmente a qualquer momento, assim: <<service docker>> db logs"
#    read -p "Pressione 'S' para confirmar ou [ENTER] para sair: " resposta
#    resposta=$(echo "$resposta" | tr '[:lower:]' '[:upper:]')  # Converter para maiúsculas
#
#    if [ "$resposta" == "S" ]; then
#      service_logs "$_service_name" $_option
#    fi
  else
    echo "$COMPOSE up $_option $_service_name"
    error_message=$($COMPOSE up $_option "$_service_name" 2>&1 | tee /dev/tty)
    container_failed_to_initialize "$error_message" "$_service_name" $_option
  fi

  if [ "$_service_name" != "$SERVICE_DB_NAME" ] && is_container_running "$_service_name"; then
    service_db_wait

    # Altera o valor de max_locks_per_transaction no sistema do PostgreSQL
    # temporariamente par a sessão atual: SET max_locks_per_transaction = 250;
    # permanentemente: ALTER SYSTEM SET max_locks_per_transaction = 250;
    psql="psql -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER -d $POSTGRES_DB"
    local psql_cmd="$_psql -tc 'ALTER SYSTEM SET max_locks_per_transaction = ${POSTGRES_MAX_LOCKS_PER_TRANSACTION:-250};'"
    $COMPOSE exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$SERVICE_DB_NAME" sh -c "$psql_cmd"
  fi

}

function command_web_django_manage() {
  local _service_name="$1"
  shift # Remover o primeiro argumento posicional ($1) -- Remove o nome do serviço da lista de argumentos
  local _option="$@"
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  database_wait

  if docker container ls | grep -q "${COMPOSE_PROJECT_NAME}-${_service_name}-1"; then
    service_exec "$_service_name" python manage.py $_option
  else
    service_run "$_service_name" python manage.py $_option
  fi
}

function command_web_test_behave() {
  local _service_name="$1"
  shift # Remover o primeiro argumento posicional ($1) -- Remove o nome do serviço da lista de argumentos
  local _option="$*"
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  database_wait

  $COMPOSE exec -T "$SERVICE_DB_NAME" bash -c "source /scripts/create_template_testdb.sh && check_template_testdb_exists '$POSTGRES_HOST' '$POSTGRES_PORT' '$POSTGRES_USER' '$POSTGRES_DB' '$POSTGRES_PASSWORD' '$TEMPLATE_TESTDB'"
  _return_func=$?
  if [ "$_return_func" -eq 0 ]; then
      echo_warning "Database template \"$TEMPLATE_TESTDB\" existe!"
      sleep 0.5
  else
    echo_info "Deseja rodar o teste a partir de um database template?"
    read -p "Pressione 'S' para confirmar ou [ENTER] para ignorar: " resposta
    resposta=$(echo "$resposta" | tr '[:lower:]' '[:upper:]')  # Converter para maiúsculas

    if [ "$resposta" == "S" ]; then
      # Chama a função create_template_testdb passando os argumentos necessários
      echo ">>> $COMPOSE exec -T $SERVICE_DB_NAME ' bash -c \"source /scripts/create_template_testdb.sh && create_template_testdb '$POSTGRES_HOST' '$POSTGRES_PORT' '$POSTGRES_USER' '$POSTGRES_DB' '*********' '$TEMPLATE_TESTDB' \""

      $COMPOSE exec -T "$SERVICE_DB_NAME" bash -c "source /scripts/create_template_testdb.sh && create_template_testdb '$POSTGRES_HOST' '$POSTGRES_PORT' '$POSTGRES_USER' '$POSTGRES_DB' '$POSTGRES_PASSWORD' '$TEMPLATE_TESTDB'"
      _return_func=$?
      if [ $_return_func -eq 0 ]; then
        echo_success "Template \"$TEMPLATE_TESTDB\" criado com sucesso!"
        echo_info "Edite o arquivo de configuração ($SETTINGS_LOCAL_FILE) e inclua na variável DATABASES as linhas:
DATABASES = {
    'default': {
        ...
        'TEST': {
            'TEMPLATE': 'template_testdb',
        },
    }
}
      "
      echo_info "Execute novamente o <<service docker>> para dar continuidade com os testes."
      exit 0
      else
        echo_error "Faha ao criar o database template de teste."
        exit 1
      fi
    fi
  fi

  command="python manage.py test_behave --behave_format progress --behave_stop --noinput"
  if docker container ls | grep -q "${COMPOSE_PROJECT_NAME}-${_service_name}-1"; then
    service_exec "$_service_name" "$command" $_option
  else
    service_run "$_service_name" "$command" $_option
  fi
}

function command_web_django_debug() {
  local _service_name="$1"
  shift # Remover o primeiro argumento posicional ($1) -- Remove o nome do serviço da lista de argumentos
  local _port="$1"
  shift
  local _option="$*"
  local execucao_liberada=true
  echo ">>> ${FUNCNAME[0]} $_service_name $_port $_option"

  if [ -z "$_port" ]; then
    _port="$APP_PORT"
    echo_warning "Porta não fornecida, usando valor padrão $_port."
  fi
  if ! check_port "$_port"; then
    echo_error "A porta $_port está em uso. Impossível continuar!"
    echo_info "Execute o comando novamente passando um número de porta diferente,
     Exemplo: <<service docker>> web debug 8002
     Outra alternativa é encerre o serviço que está usando essa porta."
    exit 1
  fi

  declare -a _name_services
  get_dependent_services "$SERVICE_WEB_NAME" _name_services
  for _sname in "${_name_services[@]}"; do
    is_container_running "$_sname"
    _return_func=$?
    if [ "$_return_func" -eq 1 ]; then
      execucao_liberada=false
      echo_info "Caso queira inicializar o serviço \"${_sname}\", execute \"<<service docker>> $_sname up -d\"."
    fi
  done
  if [ "$execucao_liberada" = false ]; then
    echo_warning "Este comando (${_service_name}) depende dos serviços listados acima para funcionar."
    echo_info "Você pode inicializar todos eles subindo o serviço \"${_service_name}\" (\"<<service docker>> ${_service_name} up\") e
    executando \"<<service docker>> ${_service_name} debug <<port_number>>\" em outro terminal."
    exit 1
  fi

  database_wait
  export "APP_PORT=${_port}"
  echo ">>> $COMPOSE run --rm -w $WORK_DIR -u $USER_NAME --service-ports $_service_name python manage.py runserver_plus 0.0.0.0:${_port} $_option"
  $COMPOSE run --rm -w $WORK_DIR -u $USER_NAME --service-ports "$_service_name" python manage.py runserver_plus 0.0.0.0:${_port} $_option
  export "APP_PORT=${APP_PORT}"
}

function command_pre_commit() {
  local _service_name="$1"
  shift # Remover o primeiro argumento posicional ($1) -- Remove o nome do serviço da lista de argumentos
  local _option="$@"
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"
#
  if docker container ls | grep -q "${COMPOSE_PROJECT_NAME}-${_service_name}-1"; then
    echo ">>> $COMPOSE exec $_service_name bash -c \"id && git config --global --add safe.directory $WORK_DIR && pre-commit run $_option --from-ref origin/${GIT_BRANCH_MAIN} --to-ref HEAD\""
    $COMPOSE exec "$_service_name" bash -c "id && git config --global --add safe.directory $WORK_DIR && pre-commit run $_option --from-ref origin/${GIT_BRANCH_MAIN} --to-ref HEAD"
  else
    echo ">>> $COMPOSE run --rm -w $WORK_DIR -u $USER_NAME --no-deps $_service_name bash -c \"id && git config --global --add safe.directory $WORK_DIR && pre-commit run $_option --from-ref origin/${GIT_BRANCH_MAIN} --to-ref HEAD\""
    $COMPOSE run --rm -w $WORK_DIR -u $USER_NAME --no-deps "$_service_name" bash -c "id && git config --global --add safe.directory $WORK_DIR && pre-commit run $_option --from-ref origin/${GIT_BRANCH_MAIN} --to-ref HEAD"
  fi
}

function command_git() {
  local _service_name="$1"
  shift # Remover o primeiro argumento posicional ($1) -- Remove o nome do serviço da lista de argumentos
  local _option="$@"
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

#  command_pre_commit "$_service_name" $_option

  if docker container ls | grep -q "${COMPOSE_PROJECT_NAME}-${_service_name}-1"; then
    echo ">>> $COMPOSE exec $_service_name bash -c \"git $_option\""
    $COMPOSE exec "$_service_name" bash -c "git $_option"
  else
    echo ">>> $COMPOSE run --rm -w $WORK_DIR -u $USER_NAME --no-deps "$_service_name" bash -c \"git $_option\""
    $COMPOSE run --rm -w $WORK_DIR -u $USER_NAME --no-deps "$_service_name" bash -c "git $_option"
  fi
}

function _service_web_up() {
  local _service_name=$1
  shift
  local _option="$*"
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  if [ "$_option" = "--force-deploy-all" ]; then
    docker_build_all $_option
    _option="--build"
  elif [ "$_option" = "--force-deploy-dev" ]; then
    _option="--build"
  fi

  database_wait

  echo ">>> $COMPOSE up $_option $_service_name"
  error_message=$($COMPOSE up $_option "$_service_name" 2>&1 | tee /dev/tty)
  container_failed_to_initialize "$error_message" "$_service_name" $_option
}

function _service_all_up() {
  local _option="${@:1}"
  echo ">>> ${FUNCNAME[0]} $_option"

  # Chama a função e captura o array retornado
  service_names=($(get_service_names))

  # Itera sobre o array retornado pela função
  for _name_service in "${service_names[@]}"; do
    _service_up "$_name_service" -d $_option
  done
}

function _service_up() {
  local _option="${*:2}"
  local _service_name="$1"
  local _nservice
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  local arg_build=""
  if echo "$_option" | grep -q -- "--force"; then
    read _option arg_build <<< $_option
  fi

  if [ "$_service_name" = "all" ]; then
    _service_all_up" $_option"
#    $COMPOSE up $_option
  elif [ "$_service_name" = "$SERVICE_DB_NAME" ]; then
    _service_db_up "$_service_name" $_option
  elif [ "$_service_name" = "$SERVICE_WEB_NAME" ]; then
    if [ -n "$arg_build" ]; then
      _option=$arg_build
    fi
    _service_web_up "$_service_name" $_option
  else
    _nservice=$(get_server_name ${_service_name})
    echo ">>> $COMPOSE up $_option $_nservice"
#    $COMPOSE up $_option "$_nservice"
    error_message=$($COMPOSE up $_option "$_nservice" 2>&1 | tee /dev/tty)
    container_failed_to_initialize "$error_message" "$_service_name" $_option
  fi
}

function service_up() {
  local _option="${*:2}"
  local _service_name=$1
#  local _name_services=($(string_to_array $(dict_get "$ARG_SERVICE" "${DICT_SERVICES_DEPENDENCIES[*]}")))

  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  # Obtem os serviços que dependem de $A_service_name
  declare -a _name_services
  dict_get_and_convert "$_service_name" "${DICT_SERVICES_DEPENDENCIES[*]}" _name_services

  for _nservice in "${_name_services[@]}"; do
    _service_up "$_nservice" -d $_option
  done
    _service_up "$_service_name" $_option
}

function remove_all_containers() {
  local _option="${@:2}"
  local _service_name=$1
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  # Obtém todos os nomes de containers que estão listados pelo docker compose ps -a
  local container_names=$($COMPOSE ps -a --format "{{.Names}}")

  if [ -z "$container_names" ]; then
#      echo "Nenhum container encontrado para remover."
      return 0
  fi

  # Itera sobre cada nome de container e os remove
  for container in $container_names; do
      echo ">>> docker stop $container"
      docker stop "$container"

      echo ">>> docker rm $container"
      docker rm  "$container"
  done
}

function _service_down() {
  local _option="${@:2}"
  local _service_name=$1
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  if [ $_service_name = "all" ]; then
    echo ">>> $COMPOSE down --remove-orphans $_option"
    $COMPOSE down --remove-orphans $_option

    remove_all_containers "$_service_name" $_option
  else
    if docker container ls | grep -q "${COMPOSE_PROJECT_NAME}-${_service_name}-1"; then
      echo ">>> docker stop ${COMPOSE_PROJECT_NAME}-${_service_name}-1"
      docker stop ${COMPOSE_PROJECT_NAME}-${_service_name}-1

      echo ">>> docker rm ${COMPOSE_PROJECT_NAME}-${_service_name}-1"
      docker rm ${COMPOSE_PROJECT_NAME}-${_service_name}-1
    else
      echo ">>> $COMPOSE down ${_service_name} $_option"
      $COMPOSE down ${_service_name} $_option
    fi
  fi
}

function service_down() {
  local _option="${@:2}"
  local _service_name=$1
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  # Prevenção contra remoção acidental de volumes
    if echo "$_option" | grep -qE "(--volumes|-v)"; then
    echo_warning "Cuidado: O uso de --volumes ou -v pode remover os volumes do banco de dados!"
    echo_info "Tem certeza de que deseja remover os volumes? Isso pode apagar o banco de dados."
    read -p "Pressione 'S' para confirmar ou [ENTER] para ignorar: " resposta
    resposta=$(echo "$resposta" | tr '[:lower:]' '[:upper:]')  # Converter para maiúsculas

    if [ "$resposta" != "S" ]; then
      echo_warning "Operação cancelada pelo usuário."
      return 1  # Interrompe a função para evitar remoção acidental
    fi
  fi

  declare -a _name_services
  dict_get_and_convert "$_service_name" "${DICT_SERVICES_DEPENDENCIES[*]}" _name_services

  for _name_service in "${_name_services[@]}"; do
    _service_down $_name_service $_option
  done
  _service_down $_service_name $_option
}

function service_restart() {
  local _option="${@:2}"
  local _service_name=$1
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  #  if [ $_service_name = "all" ]; then
  service_down $_service_name $_option
  service_up $_service_name -d $_option
  #  else
  #    service_down $_service_name $_option
  #    service_up $_service_name -d $_option
  #  fi

}

function service_build() {
  local _service_name=$1
  local force=$2
  local _option="${@:2}"
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  # Verifica se $2 é --force e filtra
  # o argumetno --force só é utilizado na função docker_build_all
  if echo "$force" | grep -q -- "--force"; then
      _option="${@:3}"  # Pega todos os argumentos a partir de $3, removendo $2
  else
      _option="${@:2}"  # Se $2 não for --force, pega todos os argumentos a partir de $2
  fi

  docker_build_all "$force"

  echo ">>> $COMPOSE build --no-cache $SERVICE_WEB_NAME $_option"
  error_message=$($COMPOSE build --no-cache "$_service_name" $_option 2>&1 | tee /dev/tty)
  container_failed_to_initialize "$error_message" "$_service_name" $_option
}

function service_deploy() {
  local _option="${@:2}"
  local _service_name=$1
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"
  service_down "$_service_name" -v $_option
  service_build "$SERVICE_WEB_NAME" $_option
}

function service_redeploy() {
  local _option="${@:2}"
  local _service_name=$1
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"
  service_undeploy
  service_deploy
}

function service_undeploy() {
  local _option="${@:2}"
  local _service_name=$1
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"
  # Opção -v remove todos os volumens atachado
  service_down "$_service_name" -v $_option

  echo ">>> rm -rf docker/volumes"
  rm -rf docker/volumes
}

function service_status() {
  local _option="${@:2}"
  local _service_name=$1
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  echo ">>> $COMPOSE ps -a"
  $COMPOSE ps -a
}

function command_db_psql() {
  local _option="${@:2}"
  local _service_name=$1
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  service_db_wait

  echo ">>> service_exec $_service_name psql -U $POSTGRES_USER $_option"
  service_exec "$_service_name" psql -U "$POSTGRES_USER" $_option
  #-d $POSTGRES_DB $@
}

##############################################################################
### Tratamento para Ctrl+C
##############################################################################

# Função que será chamada quando o script for interrompido
function handle_sigint {
  local _option="${@:2}"
  local _service_name=$1
  echo ">>> ${FUNCNAME[0]} $_service_name $_option"

  echo "Interrompido com Ctrl+C. "
  if [ $ARG_COMMAND = "up" ]; then
   service_stop "${_service_name}" "$ARG_OPTIONS"
  fi
  exit 1
}

# Configura o trap para capturar o sinal SIGINT (Ctrl+C)
trap handle_sigint SIGINT

##############################################################################
### TRATAMENTO PARA VALIDAR OS ARGUMENTOS PASSADOS
##############################################################################
# Função principal que orquestra a execução
function main() {
#  set -x  # Ativa o modo de depuração para verificar a execução
  local arg_count=$#
  declare -a specific_commands_local
  dict_get_and_convert "$ARG_SERVICE" "${DICT_SERVICES_COMMANDS[*]}" specific_commands_local


  local services_local=($(dict_keys "${DICT_SERVICES_COMMANDS[*]}"))
#  local all_commands_local=("${specific_commands_local[@]}")
#  all_commands_local+=("${COMMANDS_COMUNS[@]}")
  local all_commands_local=("${COMMANDS_COMUNS[@]}")


  error_danger=""
  error_warning=""

  verify_arguments "$ARG_SERVICE" "$ARG_COMMAND" "${services_local[*]}" "${specific_commands_local[*]}" "${all_commands_local[*]}" "$arg_count" error_danger error_warning
  argumento_valido=$?

  # Verifica o código de saída da função
  if [ $argumento_valido -ne 1 ]; then
    if [ "$TIPO_PROJECT" = "$PROJECT_DJANGO" ]; then
      create_pre_push_hook "$COMPOSE_PROJECT_NAME" "$COMPOSE" "$SERVICE_WEB_NAME" "$USER_NAME" "$WORK_DIR" "$GIT_BRANCH_MAIN"
    fi

    # Processa os comandos recebidos
    process_command "$arg_count" "$service_exists"
  else
    print_error_messages "$error_danger" "$error_warning"
  fi
  exit 1

}

if [ "$PROJECT_ROOT_DIR" != "$SCRIPT_DIR" ]; then
  if [ "$LOGINFO" = "false" ]; then
    echo_warning "VARIÁVEL \"LOGINFO=$LOGINFO\". DEFINA \"LOGINFO=true\" PARA NÃO MAIS EXIBIR AS MENSAGENS ACIMA!"
  fi

  # Chama a função principal
  main "$@"
fi
}