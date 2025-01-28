#!/bin/bash

##############################################################################
### FUÇÕES PARA TRATAMENTO DE PERSONALIZAÇÃO DE CORES DOS TEXTOS NO TERMINAL
##############################################################################

# Definição de cores para a saída no terminal
GREEN_COLOR='\033[0;32m'   # Cor verde para sucesso
ORANGE_COLOR='\033[0;33m'  # Cor laranja para avisos
RED_COLOR='\033[0;31m'     # Cor vermelha para erros
BLUE_COLOR='\033[0;34m'    # Cor azul para informações
NO_COLOR='\033[0m'         # Cor neutra para resetar as cores no terminal

# Função para exibir avisos com a cor laranja
function echo_warning() {
  echo "${@:3}" -e "$ORANGE_COLOR WARN: $1$NO_COLOR"
}

# Função para exibir erros com a cor vermelha
function echo_error() {
  echo "${@:3}" -e "$RED_COLOR DANG: $1$NO_COLOR"
}

# Função para exibir informações com a cor azul
function echo_info() {
  echo "${@:3}" -e "$BLUE_COLOR INFO: $1$NO_COLOR"
}

# Função para exibir mensagens de sucesso com a cor verde
function echo_success() {
  echo "${@:3}" -e "$GREEN_COLOR SUCC: $1$NO_COLOR"
}

##############################################################################
### FUÇÕES PARA TRATAMENTO DE INSTALAÇÃOES DE COMANDOS UTILITÁRIOS
##############################################################################

# Função para obter o nome do sistema operacional
# Dependendo do sistema operacional (Linux, MacOS, etc.), o script retorna o nome correspondente.
function get_os_name() {
  unameOut="$(uname -s)"
  case "${unameOut}" in
  Linux*) machine=Linux ;;      # Se for Linux
  Darwin*) machine=Mac ;;       # Se for MacOS
  CYGWIN*) machine=Cygwin ;;    # Se for Cygwin
  MINGW*) machine=MinGw ;;      # Se for MinGW (Windows)
  *) machine="UNKNOWN:${unameOut}" ;;  # Se não for identificado
  esac
  echo ${machine}
}

# Variável que indica se o apt-get já foi atualizado durante a execução do script
apt_get_has_update=false

# Função genérica para instalar um comando caso ele não esteja disponível
# Recebe como parâmetros o nome do comando e outras opções (caso necessárias).
function install_command() {
  local _option="${@:2}"  # Pega as opções a partir do segundo argumento
  local _command=$1       # O primeiro argumento é o nome do comando a ser instalado
  echo ">>> ${FUNCNAME[0]} $_command $_option"

  # Verifica se o comando já está instalado
  echo ">>> command -v $_command"
  if command -v $_command &>/dev/null; then
    echo "O comando $_command está disponível."
    return
  else
    echo "O comando $_command não está disponível."
    echo "--- Iniciando processo de instalação do comando $_command ..."
  fi

  # Instalação via MacPorts (para sistemas MacOS)
  if command -v port &>/dev/null; then
    echo ">>> sudo port install $_command"
    sudo port install $_command

  # Instalação via Homebrew (para MacOS/Linux com brew)
  elif command -v brew &>/dev/null; then
    echo ">>> brew install $_command"
    brew install $_command

  # Instalação via apt-get (para distribuições Linux que utilizam apt-get)
  elif command -v apt-get &>/dev/null; then
    # Atualiza o apt-get se ainda não foi feito
    if [ "$apt_get_has_update" != true ]; then
      echo ">>> apt-get update > /dev/null"
      apt-get update -y > /dev/null
      apt_get_has_update=true
    fi
    echo ">>> apt-get install -y $_command > /dev/null"
    apt-get install -y $_command > /dev/null
  fi
}

# Funções específicas para instalar determinados comandos se não estiverem presentes no sistema

# Verifica se o comando 'ps' está instalado, e o instala caso necessário
function install_command_ps() {
  if ! command -v ps &>/dev/null; then
    install_command procps
  fi
}

# Instala o comando 'pv' (Pipeline Viewer) que monitora o progresso de dados em uma pipeline
function install_command_pv() {
  install_command pv
}

# Instala o comando 'pigz' (Parallel Gzip), uma versão paralela do gzip para compressão de dados
function install_command_pigz() {
  install_command pigz
}

# Instala o comando 'tar' para manipulação de arquivos tar
function install_command_tar() {
  install_command tar
}

# Instala o comando 'file', que identifica o tipo de arquivo
function install_command_file() {
  install_command file
}

# Instala o comando 'postgis', uma extensão do PostgreSQL para dados geoespaciais
function install_command_postgis() {
  install_command postgis
}

function install_command_net_tools() {
  # comando route
  install_command net-tools
}

function install_command_iptables() {
  install_command iptables
}

##############################################################################
### FUÇÕES PARA TRATAMENTO DE ARRAYS
##############################################################################
function in_array {
  ARRAY="$2"
  for e in ${ARRAY[*]}; do
    if [ "$e" = "$1" ]; then
      return 0
    fi
  done
  return 1
}

function dict_get() {
  # Função para buscar o valor associado a uma chave específica dentro de um "dicionário" (representado como um array de pares chave:valor).
  #
  # Parâmetros:
  #   _argkey: A chave cujo valor deseja buscar.
  #   _dict: O "dicionário" representado como um array de strings no formato "chave:valor".
  #
  # Retorno:
  #   Retorna uma lista de valores associados à chave especificada.
  #
  # Exemplo de uso:
  #   _dict=("nome:Maria" "idade:30" "cidade:Natal")
  #   cidade=$(dict_get "cidade "${_dict[@]}") # Retorna "Natal"

  local _argkey=$1  # A chave para a busca
  local _dict=$2    # O array representando o dicionário
  local _result=()  # Inicializa um array vazio para armazenar os valores encontrados

  # Loop através de cada item do array _dict
  for item in ${_dict[*]}; do
    # Extrai a chave antes do primeiro caractere ':'
    local key="${item%%:*}"

    # Extrai o valor após o primeiro caractere ':'
    local value="${item##*:}"

    # Verifica se a chave extraída corresponde à chave buscada (_argkey)
    if [ "$key" = "$_argkey" ]; then
      _result+=("$value")  # Se a chave for igual, adiciona o valor ao array _result
    fi
  done

  # Imprime os valores encontrados
  echo "${_result[@]}"
}

function dict_keys() {
  local _dict=$1
  local _keys=()

  # Itera sobre o dicionário e separa as chaves dos valores
  for item in ${_dict[*]}; do
    local key="${item%%:*}"  # Pega o que está antes do ":"
    _keys+=($key)            # Adiciona a chave ao array _keys
  done

  # Imprime todas as chaves
  echo ${_keys[*]}
}

function dict_values() {
  local _dict=$1
  local _values=()
  for item in ${_dict[*]}; do
    #    local key="${item%%:*}"
    local value="${item##*:}"
    _values+=($value)
  done
  echo ${_values[*]}
}

function string_to_array() {
  local _value=$1

  _array=(${_value//;/ })
  echo ${_array[*]}
}

function convert_semicolon_to_array() {
  local _value="$1"
  local _array_name="$2"  # Nome do array passado como string

  # Substitui os ";" (pontos e vírgulas) por espaços
  local _converted="${_value//;/ }"

  # Preenche o array dinamicamente usando eval
  eval "$_array_name=(\$_converted)"

#
## Exemplo de uso:
#SERVICES="web;vpn;db;redis"
#ARRAY_RESULT=()
#
#convert_semicolon_to_array "$SERVICES" ARRAY_RESULT
#
## Verifica o conteúdo do array:
#echo "Elementos do array:"
#for element in "${ARRAY_RESULT[@]}"; do
#  echo "$element"
#done

}

function convert_multiline_to_array() {
  local multiline_string="$1"
  local array_name="$2"  # Nome do array como string

  # Modifica o IFS para tratar as quebras de linha como delimitadores
  IFS=$'\n'

  # Itera sobre cada linha da string e adiciona ao array usando 'eval'
  for line in $multiline_string; do
      eval "$array_name+=('$line')"
  done

  # Reseta o IFS para o valor padrão
  unset IFS
}

function dict_get_and_convert() {
  local _argkey=$1
  local _dict=$2
  local _result_array_name=$3  # Nome do array de saída passado como string

  # Obtém o valor do dicionário, retorna uma string com separadores ";"
  _dict_value=$(dict_get "$_argkey" "$_dict")

  if [ -n "$_dict_value" ]; then
    # Converte a string para um array, separando pelos pontos e vírgula
    eval "$_result_array_name=(\$(IFS=';' && echo \$_dict_value))"
  else
    # Retorna um array vazio se a chave não for encontrada
    eval "$_result_array_name=()"
    return 0
  fi
}


##############################################################################
### FUNÇÕES RELACIONADAS COM INTERAÇÕES COM O POSTGRES
##############################################################################
function check_db_exists() {
    local postgres_user="$1"
    local postgres_host="${2:-localhost}"
    local postgres_port=${3:-5432}
    local postgres_password="$4"
    local postgres_db="$5"

    export PGPASSWORD=$postgres_password

    # Use psql to check if the database exists
    result=$(psql -U "$postgres_user" -h "$postgres_host" -p "$postgres_port" -tAc "SELECT 1 FROM pg_database WHERE datname='$postgres_db';")

    if [ "$result" = "1" ]; then
        return 0
    else
        return 1
    fi
    # Exemplo de uso:
    # check_db_exists "$POSTGRES_USER" "$POSTGRES_DB" "$host" "$port"
}

function is_script_initdb() {
    # Verifica se o script foi chamado pelo script de inicialização do container Postgres
    if ps -ef | grep -v grep | grep "/usr/local/bin/docker-entrypoint.sh" > /dev/null; then
        return 0  # Sucesso, foi chamado pelo script de inicialização
    # Verifica se o script foi chamado pelo comando exec ou run do docker
    elif ps -ef | grep -v grep | grep "/docker-entrypoint-initdb.d/init_database.sh" > /dev/null; then
        return 1  # Foi chamado por outro comando
    else
        echo "Chamada desconhecida."
        ps -ef
        return 1  # Retorna 1 se a chamada não for reconhecida
    fi
  # if is_script_initdb; then
  #   echo "INITDB"
  # fi
}

function is_first_initialization() {
    # Caminho para o diretório de dados do PostgreSQL
#    local PG_DATA="/var/lib/postgresql/data"

    # Verifica se o arquivo PG_VERSION existe, indicando que o PostgreSQL já foi inicializado
    if [ -f "$PG_DATA/PG_VERSION" ]; then
        echo "O PostgreSQL já foi inicializado anteriormente. Continuando normalmente..."
        return 1  # Não é a primeira inicialização
    else
        echo "O PostgreSQL está sendo inicializado pela primeira vez."
        return 0  # Primeira inicialização
    fi
}

function get_host_port() {
# Função para testar conexão ao PostgreSQL e ajustar comando psql_command
    local postgres_user="$1"
    local postgres_host="$2"
    local postgres_port="$3"
    local postgres_password="$4"

    export PGPASSWORD=$postgres_password

    # Tenta conexão com o host e porta fornecidos
    if pg_isready -u postgres_user -h "$postgres_host" -p "$postgres_port" > /dev/null 2>&1; then
        echo "$postgres_host $postgres_port"
        return 0
    fi

    # Tenta conexão com localhost e a porta padrão 5432
    if pg_isready -h "localhost" -p "5432" > /dev/null 2>&1; then
        echo "localhost 5432"
        return 0
    fi

    # Tenta conexão sem especificar o host, usando a porta fornecida
    if pg_isready -p "$postgres_port" > /dev/null 2>&1; then
        echo "localhost $postgres_port"
        return 0
    fi

    # Testa o host fornecido com a porta padrão 5432
    if pg_isready -h "$postgres_host" -p "5432" > /dev/null 2>&1; then
        echo "$postgres_host 5432"
        return 0
    fi

    # Se todas as tentativas falharem
    echo "Falha ao conectar ao PostgreSQL."
    return 1

  # Exemplo de uso
  # read host port <<< $(get_host_port "$POSTGRES_HOST" "$POSTGRES_PORT")
  # if [ $? -ne 0 ]; then
  #   echo "Não foi possível conectar ao servidor PostgreSQL."
  #   exit 1
  # fi
}

##############################################################################
### FUNÇÕES PARA TRATAMENTO DE REDES: PORTAS, ROTAS,  DOMÍNOS(/etc/hosts), ETC
##############################################################################
# Função para adicionar uma rota
function add_route() {
    local vpn_gateway="$1"
    local route_network="$2"

    if [ -n "$vpn_gateway" ] && [ -n "$route_network" ]; then
        echo "Adicionando rota para $route_network via $vpn_gateway"
        echo ">>> route add -net $route_network gw $vpn_gateway"
        route add -net $route_network gw "$vpn_gateway"
    fi
}

function update_hosts_file() {
# Função para atualizar o arquivo /etc/hosts
# Adicionar domínio no /etc/hosts
# O arquivo /etc/hosts é usado para mapear nomes de domínio a endereços IP localmente no sistema.
# Adiciona uma nova entrada, permitindo que o sistema resolva $domain_name para o endereço IP especificado em $ip.
# Isso é útil em configurações de rede onde se deseja resolver um nome de domínio personalizado,
# como em ambientes de desenvolvimento ou em situações onde o DNS público não é utilizado.

    local domain_name="$1"
    local ip="$2"

    if [ -n "$domain_name" ] && [ -n "$ip" ]; then
        echo "Adicionando $domain_name ao /etc/hosts"
        echo ">>> echo \"$ip $domain_name\" >> /etc/hosts"
        echo "$ip $domain_name" >> /etc/hosts
    fi
}

function process_hosts_and_routes() {
# Função para atualizar o /etc/hosts e verificar a tabela de rotas
    local etc_hosts="$1"  # Entrada multilinear com os domínios e IPs
    local vpn_gateway="$2"
    local route_nework="$3"
    local dict_etc_hosts=()

    install_command_net_tools

    add_route "$vpn_gateway" "$route_nework"

    # Converte o conteúdo do /etc/hosts em um array
    convert_multiline_to_array "$etc_hosts" dict_etc_hosts

    # Itera sobre cada entrada para atualizar o /etc/hosts
    for entry in "${dict_etc_hosts[@]}"; do
        local domain_name="${entry%%:*}"  # Extrai o domínio
        local ip="${entry##*:}"  # Extrai o IP
        update_hosts_file "$domain_name" "$ip"
    done

    # Verifica a tabela de rotas
    route -n
    sleep 2  # Aguarda 2 segundos
}

function check_port() {
    local _port="$1"

    if netstat -tuln | grep -q ":$_port"; then
        return 1  # Porta em uso
    else
        return 0  # Porta disponível
    fi
# # Exemplo de uso da função
  #_port="8080"
  #
  #check_port "$_port"
  #
  #if check_port "$_port"; then
  #    echo "A porta $_port está disponível."
  #else
  #    echo "A porta $_port está em uso."
  #fi
}

##############################################################################
### FUNÇÕES PARA ENCONTRAR UM IP DISPONÍVEL NO CONTAINER.
##############################################################################
# **verificar_ip_em_uso**: Verifica se um determinado intervalo de IP já está em uso,
# verificando as redes do Docker com o driver bridge.
# **encontrar_ip_disponivel**: Tenta encontrar um intervalo de IP não utilizado,
# começando em um determinado intervalo base (172.19.0.0/16, neste exemplo).
# Se o intervalo inicial (172.18.0.0/16) estiver em uso, a função tenta encontrar
# outro intervalo de IP (172.19.0.0/16, 172.20.0.0/16, etc.).
# O resultado é impresso e pode ser usado no arquivo Docker Compose.

# Função para verificar se um IP específico está em uso
function verificar_gateway_em_uso() {
    local gateway_ip="$1"
    docker network inspect --format '{{json .IPAM.Config .Labels.}}' $(docker network ls -q) | grep -q "\"Gateway\":\"$gateway_ip\"" && return 0
    return 1  # Retorna 1 se o IP do gateway não estiver em uso
}

function verificar_ip_em_uso() {
# Função para verificar se uma sub-rede está em uso
    local subnet="$1"
    docker network ls --filter driver=bridge -q | while read -r network_id; do
        docker network inspect "$network_id" --format '{{(index .IPAM.Config 0).Subnet}}' | grep -q "^$subnet$" && return 0
    done
    return 1  # Retorna 1 se a sub-rede não estiver em uso
}

# Função para encontrar uma sub-rede e IP de gateway disponíveis
# Rede clase C, prefixo /16
function encontrar_ip_disponivel() {
    local base_ip="$1"  # Ex: "172.19"
    local mask="$2"     # Ex: "16"
    local terceiro_octeto=0
    # Testar uma série de sub-redes começando no base_ip
    while [ "$terceiro_octeto" -lt 255 ]; do
        # Construir a sub-rede e o IP do gateway
        subnet="${base_ip}.${terceiro_octeto}.0/${mask}"
        gateway_ip="${base_ip}.${terceiro_octeto}.2"

        # Verificar se a sub-rede ou o gateway já estão em uso
        if ! verificar_ip_em_uso "$subnet" && ! verificar_gateway_em_uso "$gateway_ip"; then
            echo "$subnet $gateway_ip"
            return 0  # Retornar a sub-rede e o IP do gateway disponíveis
        fi

        # Incrementar o segundo octeto para tentar o próximo intervalo de IP
        terceiro_octeto=$((terceiro_octeto + 1))
    done

    echo "Erro: Nenhuma sub-rede ou IP de gateway disponível encontrado."
    return 1
}

function determinar_gateway_vpn() {
# Função para determinar a sub-rede e o IP do gateway
    local default_vpn_gateway_faixa_ip="172.19.0.0/16"
    local default_vpn_gateway_ip="172.19.0.2"
    local base_ip="172.19"
    local mask="16"

    # Verificar se o gateway inicial está em uso
    if verificar_gateway_em_uso "$default_vpn_gateway_ip"; then
#        echo_warning "IP do gateway $default_vpn_gateway_ip já está em uso."

        # Encontrar um novo IP de gateway disponível
        local resultado=$(encontrar_ip_disponivel "$base_ip" "$mask")

        if [ $? -eq 0 ]; then
            default_vpn_gateway_faixa_ip=$(echo "$resultado" | cut -d ' ' -f 1)
            default_vpn_gateway_ip=$(echo "$resultado" | cut -d ' ' -f 2)
#            echo_warning "Nova sub-rede e IP de gateway disponíveis: $default_vpn_gateway_faixa_ip, Gateway: $default_vpn_gateway_ip"
        else
            echo_error "Não foi possível encontrar uma sub-rede ou IP de gateway disponível."
            exit 1
        fi
#    else
#        echo_info "Sub-rede $default_vpn_gateway_faixa_ip e gateway $default_vpn_gateway_ip estão disponíveis."
    fi

    # Retornar os valores
    echo "$default_vpn_gateway_faixa_ip $default_vpn_gateway_ip"

# # Exemplo de uso da função
  #resultado=$(determinar_gateway_vpn)
  #vpn_gateway_faixa_ip=$(echo "$resultado" | cut -d ' ' -f 1)
  #vpn_gateway_ip=$(echo "$resultado" | cut -d ' ' -f 2)
  #
  #echo "VPN Gateway Faixa IP: $vpn_gateway_faixa_ip"
  #echo "VPN Gateway IP: $vpn_gateway_ip"
}

function verificar_subrede_na_faixa() {
    local subrede="$1" # Sub-rede que queremos verificar, ex: 192.168.1.0/24
    local faixa="$2"   # Faixa a ser comparada, ex: 192.168.0.0/16

    # Verifica se a sub-rede está dentro da faixa maior usando ipcalc
    ipcalc -n "$subrede" "$faixa" 2>/dev/null | grep -q "overlap" && {
        echo "A sub-rede $subrede está dentro da faixa $faixa."
        return 0
    }
    echo "A sub-rede $subrede NÃO está dentro da faixa $faixa."
    return 1
}

function verificar_sobreposicao_subrede() {
    local subnet="$1" # Sub-rede que queremos verificar, ex: 172.19.0.0/16
    local rede_encontrada=""
    local conflito=1 # Inicializa como sem conflito

#    echo "Verificando sobreposição para a sub-rede: $subnet"
    # Itera sobre todas as redes Docker
    while read -r network_id; do
        # Obtém o nome e a sub-rede da rede atual, se disponíveis
        local nome_rede
        local rede_subnet

        nome_rede=$(docker network inspect --format '{{.Name}}' "$network_id")
        rede_subnet=$(docker network inspect --format '{{if (index .IPAM.Config 0)}}{{(index .IPAM.Config 0).Subnet}}{{end}}' "$network_id")

        # Ignora redes sem sub-rede definida
        if [ -z "$rede_subnet" ]; then
            continue
        fi

#        echo "Verificando rede: $nome_rede (sub-rede: $rede_subnet)"

        # Verifica sobreposição de sub-redes (usar lógica ou ferramentas como ipcalc/sipcalc)
        # TODO: Ideal usar verificar_subrede_na_faixa, porém como depende do
        #  pacote ipcalc, preferimos não usar para não ter que instalar
        #  pacotes adicionais
        if [ "$subnet" = "$rede_subnet" ]; then
            rede_encontrada="$nome_rede"
            conflito=0
            break
        fi
    done < <(docker network ls -q) # Redireciona a saída diretamente ao `while`

    # Retorna o nome da rede encontrada, se houver
    if [ $conflito -eq 0 ]; then
        echo "$rede_encontrada"
    fi

    return $conflito

    # Exemplo de uso:
    # rede_conflitante=$(verificar_sobreposicao_subrede "172.19.0.0/16")
    # if [[ $? -eq 0 ]]; then
    #    echo "Rede em conflito: $rede_conflitante"
    # else
    #    echo "Nenhuma rede em conflito."
    # fi
}

function encontrar_subrede_disponivel() {
    local cidr_base="$1"    # Base da sub-rede, ex: "192.168.0.0"
    local cidr_range="$2"   # Tamanho do CIDR, ex: 24
    local max_subnets="$3"  # Número máximo de sub-redes para testar, ex: 100
    local subnet_disponivel=""
    local ip_sugerido=""

#    echo "Buscando sub-rede disponível na faixa $cidr_base/$cidr_range..."

    # Obter todas as sub-redes ocupadas atualmente no Docker
    local subredes_ocupadas=($(docker network ls -q | xargs docker network inspect --format '{{if (index .IPAM.Config 0)}}{{(index .IPAM.Config 0).Subnet}}{{end}}' 2>/dev/null | grep -v '^$'))

    # Itera gerando sub-redes a partir da base e verificando disponibilidade
    for i in $(seq 0 $((max_subnets - 1))); do
        # Calcula a próxima sub-rede adicionando `i` ao terceiro octeto
        local subnet=$(echo "$cidr_base" | awk -v inc="$i" -F '.' '{printf "%d.%d.%d.%d/%s", $1, $2, ($3 + inc), 0, "'"$cidr_range"'"}')

        # Verifica se a sub-rede está ocupada
        local conflito=0
        for rede in "${subredes_ocupadas[@]}"; do
            if [[ "$rede" == "$subnet" ]]; then
                conflito=1
                break
            fi
        done

        # Se não houver conflito, a sub-rede está disponível
        if [[ $conflito -eq 0 ]]; then
            subnet_disponivel="$subnet"
            # Calcula o IP sugerido: primeiro endereço disponível na sub-rede (ex.: 192.168.1.1 para 192.168.1.0/24)
            ip_sugerido=$(echo "$subnet" | awk -F '/' '{split($1, octets, "."); printf "%d.%d.%d.%d", octets[1], octets[2], octets[3], octets[4] + 1}')
#            echo "Sub-rede disponível: $subnet_disponivel"
#            echo "IP sugerido para uso: $ip_sugerido"
            break
        fi
    done

    # Retornar a sub-rede e o IP sugerido
    if [[ -z "$subnet_disponivel" ]]; then
#        echo "Nenhuma sub-rede disponível encontrada na faixa fornecida."
        return 1
    else
        echo "$subnet_disponivel $ip_sugerido"
        return 0
    fi

   # Exemplo de uso:
   # Procurar uma sub-rede na faixa 192.168.0.0/24, testando até 100 sub-redes
   #resultado=$(encontrar_subrede_disponivel "192.168.0.0" 24 100)
   #
   #if [[ $? -eq 0 ]]; then
   #    # Extrair sub-rede e IP sugerido da saída
   #    subrede=$(echo "$resultado" | awk '{print $1}')
   #    ip_sugerido=$(echo "$resultado" | awk '{print $2}')
   #    echo "Sub-rede encontrada: $subrede"
   #    echo "IP sugerido para uso: $ip_sugerido"
   #else
   #    echo "Nenhuma sub-rede disponível encontrada."
   #fi
}


##############################################################################
### FUNÇÕES PARA TRATAR TRATAMENTO DE IMAGENS DOCKER, DOCKERFILE E DOCKER-COMPOSE
##############################################################################

# Função para verificar se a imagem Docker existe
verifica_imagem_docker() {
    local imagem="$1"
    local tag="${2:-latest}"  # Se nenhuma tag for fornecida, usa "latest"

    # Verifica se a imagem já existe localmente
    if docker image inspect "${imagem}:${tag}" > /dev/null 2>&1; then
        return 0  # Retorna 0 se a imagem existir
    else
        return 1  # Retorna 1 se a imagem não existir
    fi
# # Exemplo de uso da função
  #IMAGEM="python-nodejs-dev"
  #TAG="latest"
  #
  ## Chamada da função
  #if verifica_imagem_docker "$IMAGEM" "$TAG"; then
  #    echo "Processando com a imagem existente..."
  #else
  #    echo "Você precisa construir ou baixar a imagem."
  #fi
}

function escolher_imagem_base() {
# Função para exibir as opções de imagens e retornar a escolha do usuário
    echo >&2 "Selecione uma das opções de imagem base para seu projeto:"
    echo >&2 "1. Imagem base de desenvolvimento Python"
    echo >&2 "2. Imagem base de desenvolvimento Python com Node.js."
    echo >&2 "3. Vou usar minha própria imagem."

    # Solicitar entrada do usuário
    read -p "Digite o número correspondente à sua escolha: " escolha

    # Definir a imagem base com base na escolha
    case $escolha in
        1)
            imagem_base="python_base_dev"
            ;;
        2)
            imagem_base="python_nodejs_dev"
            ;;
        3)
            imagem_base="default"
            ;;
        *)
            echo_warning >&2 "Escolha inválida. Por favor, escolha uma opção válida."
            escolher_imagem_base  # Chama a função novamente em caso de escolha inválida
            return
            ;;
    esac

    # Retorna a imagem base selecionada
    echo "$imagem_base"

# Exemplo de uso
#resultado=$(escolher_imagem_base)
#imagem_base=$(echo $resultado | awk '{print $1}')
#nome_base=$(echo $resultado | awk '{print $2}')
#
#echo "Imagem selecionada: $imagem_base"
#echo "Nome base: $nome_base"
}

#!/bin/bash

# Função para verificar se o serviço usa Dockerfile
function verificar_servico_usa_dockerfile() {
    local arquivo_compose="$1" # Caminho para o arquivo docker-compose.yaml
    local servico="$2"  # Nome do serviço a verificar
    set -x
    # Verifica se o arquivo docker-compose.yaml existe
    if [ ! -f "$arquivo_compose" ]; then
        echo "Erro: Arquivo $arquivo_compose não encontrado."
        return 1
    fi

    # Verifica se o serviço usa 'build'
    if grep -A 10 "services:" "$arquivo_compose" | grep -A 10 "$servico:" | grep -q "build:"; then
        return 0  # Serviço usa Dockerfile
    else
        return 1  # Serviço não usa Dockerfile
    fi
    # Exemplo de uso
    #servico="django"
    #verificar_servico_usa_dockerfile "$servico"
    #
    #if [[ $? -eq 0 ]]; then
    #    echo "O serviço '$servico' usa um Dockerfile."
    #else
    #    echo "O serviço '$servico' não usa um Dockerfile."
    #fi
}

##############################################################################
### TRATAMENTOS PARA ARQUIVO .INI
##############################################################################

function get_filename_path() {
    local dir_path="$1"
    local ini_file_path="$2"
    local section="$3"
    local key="$4"
    local default_filename_path=""
    local filename_path=""

    # Lê o valor da chave "default" na seção "$section"
    default_filename_path=$(read_ini "$ini_file_path" "$section" "default" | tr -d '\r')
    if [ ! -z "$filename_path" ]; then
      default_filename_path="${dir_path}/${default_filename_path}"
    fi

    # Lê o valor da chave correspondente ao projeto na seção "envfile"
    filename_path=$(read_ini "$ini_file_path" "$section" "$key" | tr -d '\r')
    if [ -z "$filename_path" ]; then
        filename_path="$default_filename_path"
    fi

    # Retorna o valor da variável _project_file
    echo "$filename_path"
}

function list_keys_in_section() {
    local ini_file_path="$1"
    local section="$2"
    local array_name="$3"  # Nome do array passado como string

    # Inicializa o array como vazio
    eval "$array_name=()"

    # Extrai as chaves da seção especificada
    while read -r line; do
        if [[ $line =~ ^\[.*\] ]]; then
            break  # Encerra ao encontrar outra seção
        elif [[ $line =~ ^[^#]*= ]]; then
            key=$(echo "$line" | awk -F= '{print $1}')
            eval "$array_name+=('$key')"  # Adiciona a chave ao array dinamicamente
        fi
    done < <(awk "/^\[$section\]/ {flag=1; next} /^\[/ {flag=0} flag {print}" "$ini_file_path")

# Exemplo de uso
#declare -a keys
#list_keys_in_section "config.ini" "extensions" keys
#
## Exibe as chaves
#for key in "${keys[@]}"; do
#    echo "$key"
#done
}

##############################################################################
### TRATAMENTOS VARIÁVEIS ARQUIVO .ENV
##############################################################################
function insert_text_if_not_exists() {
  # Função para inserir o texto no início do arquivo .env, caso não exista
    local force="false"
    if [ "$1" = "--force" ]; then
        force="true"
        shift  # Remove o parâmetro --force da lista de argumentos
    fi
    local text="$1"
    local env_file="$2"
    local key=$(echo "$text" | cut -d '=' -f 1)

    # Verificar se a chave está definida no arquivo, se não for forçado
    # Força a inserção sem verificação se a chave existe no arquivo $env_file
    if [ "$force" = "true" ]; then
        # Verifica se o texto está vazio.
        if [ -z "$text" ]; then
          # Adiciona uma quebra de linha
          sed -i '1i\\' "$env_file"
        else
          sed -i "1i$text" "$env_file"
        fi
        echo_warning "-- Texto '$text' adicionado ao início do arquivo $env_file (forçado)"
    elif ! grep -q "^$key=" "$env_file"; then
        # Se a chave não estiver definida, inserir no início do arquivo
        sed -i "1i$text" "$env_file"
        echo_warning "-- Texto '$text' adicionado ao início do arquivo $env_file"
    fi
# Exemplo de uso:
# insert_text_if_not_exists "UID=1000" ".env"
# insert_text_if_not_exists --force "UID=1000" ".env"
}

function imprime_variaveis_env() {
  local env_file_path="$1"

  while IFS= read -r line; do

    # Ignora linhas em branco ou comentários
    if [ -n "$line" ] && ! expr "$line" : '#.*' > /dev/null; then
      # Extrai o nome da variável e o valor, com base no formato "chave=valor"
      var_name=$(echo "$line" | cut -d'=' -f1)
      var_value=$(echo "$line" | cut -d'=' -f2-)

      # Verifica se o nome da variável é válido
      if [[ "$var_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
          echo "$var_name=$var_value"
      else
        # Se o nome da variável for inválido, apenas exibe a linha lida
         echo "$var_name"
      fi
    fi
  done <"$env_file_path"

# ver apenas as variáveis definidas no próprio script,
#set

# ver todas as variáveis, incluindo as variáveis locais e as de ambiente no script,
#declare -p
  # declare -x:
  #Função: Exporta a variável, tornando-a disponível para processos filhos.
  #Exemplo: declare -x VAR="value" faz com que VAR seja visível para qualquer processo que o script iniciar.
  #
  #declare -i:
  #Função: Faz com que a variável seja tratada como um inteiro (número).
  #Exemplo: declare -i NUM=10 significa que NUM só aceitará valores inteiros. Se você tentar atribuir um valor não numérico, ele será interpretado como zero.
  #
  #declare --:
  #Função: Usado para marcar o fim das opções, útil quando uma variável pode começar com um -. Isso impede que o Bash interprete o valor da variável como uma opção de comando.
  #Exemplo: declare -- VAR="value" assegura que "VAR" não será tratado como uma opção.
  #
  #declare -r:
  #Função: Torna a variável somente leitura. Não pode ser alterada após sua atribuição.
  #Exemplo: declare -r VAR="value" significa que você não pode modificar VAR posteriormente.
  #
  #declare -ir:
  #Função: Combina as opções -i e -r, tornando a variável um número inteiro e somente leitura.
  #Exemplo: declare -ir NUM=100 significa que NUM é um inteiro e não pode ser modificado.
  #
  #declare -a:
  #Função: Define a variável como um array indexado numericamente.
  #Exemplo: declare -a ARRAY define ARRAY como um array, permitindo atribuir e acessar valores como ARRAY[0], ARRAY[1], etc.
  #
  #declare -A:
  #Função: Define a variável como um array associativo (ou hash), onde as chaves podem ser strings.
  #Exemplo: declare -A HASH permite que você use chaves do tipo string, como HASH["key"]="value".
  #
  #declare -ar:
  #Função: Define a variável como um array somente leitura.
  #Exemplo: declare -ar ARRAY significa que o array ARRAY não pode ser alterado após sua criação.
}
##############################################################################
### TRATAMENTOS PARA ARQUIVOS E DIRETÓRIOS
##############################################################################
function check_file_existence() {
# Função para verificar se existe um arquivo no path fornecido, com extensões opcionais
  local file_path="$1"
  shift
  local extensions=("$@")

  # Verifica se o arquivo especificado no caminho existe
  if [ -f "$file_path" ]; then
    return 0  # Arquivo encontrado diretamente
  fi

  # Caso o arquivo exato não exista e haja extensões fornecidas, verifica com
  # as extensões
  if [ "${#extensions[@]}" -gt 0 ]; then
    for ext in "${extensions[@]}"; do
      if [ -f "${file_path%.*}.$ext" ]; then
        return 0  # Arquivo com uma das extensões encontradas
      fi
    done
  fi

  return 1  # Nenhum arquivo com o path ou as extensões fornecidas foi encontrado

  ## Exemplo de uso da função
  #docker_file_or_compose_path="/caminho/para/docker-compose"
  #if check_file_existence "$docker_file_or_compose_path" "yml" "yaml"; then
  #  echo "Arquivo encontrado."
  #else
  #  echo "Arquivo não encontrado."
  #fi
}

function os_path_join() {
    local path=""
    local first_arg=true

    for segment in "$@"; do
        # Remove barras extras no início ou no final de cada segmento
        segment="${segment#/}"
        segment="${segment%/}"

        # Lida com caminhos relativos contendo "./"
        if [[ "$segment" == "./"* ]]; then
            segment="${segment#./}"
        fi

        # Concatena o caminho com "/"
        if [[ "$first_arg" == true ]]; then
            path="$segment"
            first_arg=false
        else
            path="${path}/${segment}"
        fi
    done

    # Garante que mantenha a barra inicial se o primeiro segmento for absoluto
    [[ "${1:0:1}" == "/" ]] && path="/${path}"

    # Remove redundâncias manualmente, como "/./" e "//"
    path=$(echo "$path" | sed 's:/\./:/:g; s://:/:g; s:/$::')

    echo "$path"

    # Exemplo de chamada:
    # final_path=$(os_path_join "/home" "/jailton/" "workstation//" "./djud/djud")
    # echo "$final_path"
    ## Saída esperada: /home/jailton/workstation/djud/djud
}


##############################################################################
### TRATAMENTOS PARA PLUGINS DE EXTENSÕES
##############################################################################
function extension_exec_script() {
  local inifile_path="$1"
  local command="$2"
  local arg_command="$3"
  local options="${*:4}" # Pega todos os argumentos a partir do quarto

  local arg_count=$#
  local script_path_or_url=""
  local dir_path=""
  local url=""
  local script_name="${arg_command}.sh"

  echo ">>> ${FUNCNAME[0]} $inifile_path $command $arg_command $options"

  # Substituir `declare -a` por arrays normais
  local comandos_disponiveis=()

  # Preencher o array com as chaves disponíveis na seção do arquivo INI
  list_keys_in_section "$inifile_path" "extensions" comandos_disponiveis

  if [ -z "$arg_command" ]; then
    echo_error "Nome do projeto base não existe. Impossível continuar."
    echo_info "Deve informar o nome do projeto base que deseja gerar.
    Projetos base disponíveis: ${comandos_disponiveis[*]}"
    exit 1
  fi

  if [ "$arg_count" -ge 1 ]; then
    if ! in_array "$arg_command" "${comandos_disponiveis[*]}"; then
      echo_error "Argumento [$arg_command] não existe para o comando [$command]."
      echo_warning "Projetos base disponíveis: ${comandos_disponiveis[*]}"
      exit 1
    else
      script_path_or_url=$(get_filename_path "$PROJECT_DEV_DIR" "$inifile_path" "extensions" "$arg_command")

      # Verifica se o arquivo existe
      if [ ! -f "$script_path_or_url" ]; then
          if echo "$script_path_or_url" | grep -qE '^https?://'; then
              echo_info "URL HTTP(S) detectada: $script_path_or_url"
          elif echo "$script_path_or_url" | grep -qE '^[^@]+@[^:]+:.+'; then
              echo_info "URL SSH detectada: $script_path_or_url"
          else
              echo_error "Script $script_path_or_url não encontrado"
              echo_info "Verifique o caminho (path) do arquivo do script."
              exit 1
          fi
          url=$script_path_or_url

          dir_path="${options%% *}"
          if [ -z "$dir_path" ]; then
            echo_error "Diretório não informado."
            echo_info "Informe o diretório onde o projeto será gerado."
            exit 1
          fi

          if [ ! -d "$dir_path" ]; then
            echo_error "Diretório \"${dir_path}\" não encontrado."
            echo_info "Informe um diretório válido onde o projeto será gerado."
            exit 1
          fi

          echo "--- Iniciando o download do script $script_path_or_url no diretório $dir_path ..."

          url_last_part=$(basename "$url")
          dir_destination_path=$(os_path_join "$dir_path" "$url_last_part")

          git clone "$url" "$dir_destination_path"
          if [[ $? -eq 128 ]]; then
            echo_warning "Diretório $dir_destination_path já existe e não está vazio."
          fi

          script_path=$(os_path_join "$dir_destination_path" "$script_name")

          if [ -f "$script_path" ]; then
              chmod +x "$script_path"
          else
              echo_error "Erro: O script $script_path não foi encontrado."
              exit 1
          fi
      else
        script_path=$script_path_or_url
      fi

      echo_info "Script $script_path detectado. Iniciando a execução..."
      chmod +x "$script_path"

      if [ -f "$script_path" ]; then
        echo ">>> $script_path $options"
        "$script_path" $options
      else
        echo_error "O arquivo $script_path não encontrado."
        exit 1
      fi
    fi
  fi
}

##############################################################################
### OUTRAS FUNÇÕES
##############################################################################
function check_command_status_on_error_exit() {
  # Com mensagem de sucesso:
  # some_command
  # check_command_status "Falha ao executar o comando." "Comando executado com sucesso!"
  #
  # Sem mensagem de sucesso:
  # some_command
  # check_command_status "Falha ao executar o comando."

  local exit_code=$1
  local error_message="$2"
  local success_message="$3"

  if [ $exit_code -ne 0 ]; then
      # Exibe a mensagem de erro e interrompe a execução do script
      echo_error "$error_message"
      exit 1
  else
      # Se sucesso e a mensagem de sucesso foi fornecida, exibe a mensagem de sucesso
      if [ -n "$success_message" ]; then
          echo_success "$success_message"
      fi
  fi
}

function verificar_comando_inicializacao_ambiente_dev() {
    # Função para verificar o comando de inicialização da aplicação no ambiente de desenvolvimento
    local root_dir="$1"
    local ini_file_path="$2"
    local tipo_projeto=""
    local mensagem=""

    # Array para armazenar pares chave:condição
    local environment_conditions=()

    # Ler a seção "environment_dev_existence_condition" e preencher o array
    if read_section "$ini_file_path" "environment_dev_existence_condition" environment_conditions; then
        # Itera sobre os pares chave:condição
        for entry in "${environment_conditions[@]}"; do
            local key="${entry%%:*}"          # Chave antes do ":"
            local condicao="${entry#*:}"      # Valor após o ":"

            # Avalia a condição
            if eval "$condicao"; then
                mensagem=$(read_ini "$ini_file_path" "environment_dev_names" "$key" | tr -d '\r')
                echo "$key $mensagem"
                return 0
            fi
        done
    else
        echo "Erro: Seção não encontrada ou arquivo não existe."
        return 1
    fi

    echo "INDEFINIDO Não foram encontrados arquivos ou diretórios que indiquem a presença de um ambiente de desenvolvimento."
    return 1
}


function create_pre_push_hook() {
  local compose_project_name="$1"
  local compose_command="$2"
  local service_name="$3"
  local username="$4"
  local workdir="$5"
  local gitbranch_name="$6"

  # Verifica se o arquivo pre-push já existe
  if [ ! -f .git/hooks/pre-push ]; then
    # Cria o arquivo pre-push com o conteúdo necessário
    cat <<EOF > .git/hooks/pre-push
#!/bin/sh

# Executa o comando pre-commit customizado
# - "git config --global --add safe.directory" permite que o diretório especificado seja marcado como seguro, permitindo que o Git execute operações nesse diretório.
# - "--from-ref origin/\${GIT_BRANCH_MAIN:-master}" especifica o commit de origem para a comparação.
#  Por padrão, o commit de origem será a referência da branch principal
# - "--to-ref HEAD" define que o commit final para comparação é o HEAD, ou seja, o commit mais recente na branch atual.
# - "pre-commit run" executa os hooks de pre-commit definidos no arquivo .pre-commit-config.yaml
if [ -d "$workdir" ]; then
  git config --global --add safe.directory ${workdir:-/opt/suap} && pre-commit run --from-ref origin/${gitbranch_name:-master} --to-ref HEAD
elif docker container ls | grep -q "${compose_project_name}-${service_name}-1"; then
  $compose_command exec -T $service_name bash -c "git config --global --add safe.directory ${workdir:-/opt/suap} && pre-commit run --from-ref origin/${gitbranch_name:-master} --to-ref HEAD"
else
  $compose_command run --rm -w $workdir -u $username --no-deps "$service_name" bash -c "git $_option"
fi

# Verifica se o script foi executado com sucesso
if [ \$? -ne 0 ]; then
  echo "Falha no pre-commit, push abortado."
  exit 1
fi
EOF
    # Torna o arquivo pre-push executável
    chmod +x .git/hooks/pre-push
    echo "Arquivo pre-push criado com sucesso."
#  else
#    echo "Arquivo pre-push já existe."
  fi
}

function verificar_e_atualizacao_repositorio() {
# Função para verificar atualizações na branch main de um repositório específico
    local repo_path="$1"
    local repo_url="$2"
    local intervalo_dias="$3"
    local branch="${4:-main}"

    # Verifica se o diretório do repositório existe
    if [[ ! -d "$repo_path" ]]; then
        echo_error "O diretório $repo_path não existe."
        return 1
    fi

    local check_file="/tmp/ultima_verificacao_atualizacao.txt"
    local today=$(date +%Y-%m-%d)

    # Verifica se o intervalo de dias é um número válido
    if [[ ! "$intervalo_dias" =~ ^[0-9]+$ ]]; then
        echo_error "O intervalo de dias deve ser um número inteiro."
        return 1
    fi

    # Calcula a data limite para a próxima verificação em segundos
    local limite_tempo=$((intervalo_dias * 86400))  # 86400 segundos em um dia

    # Verifica se já passou o intervalo de dias desde a última verificação
    if [ -f "$check_file" ]; then
        local ultima_verificacao=$(cat "$check_file")
        local diff=$((today - ultima_verificacao))

        if (( diff < limite_tempo )); then
            #A última verificação foi há menos de $intervalo_dias dias.
            return 0
        fi
    fi

    echo "--- Verificando se o diretório especificado é um repositório Git..."
    if ! git -C "$repo_path" rev-parse --is-inside-work-tree &>/dev/null; then
        echo_error "Erro: O diretório $repo_path não é um repositório Git."
        return 1
    fi

    echo "--- Verificando se o repositório está atualizado.
    Aguarde um momento ..."
    # Buscando atualizações do repositório remoto.
    git -C "$repo_path" fetch "$repo_url" "$branch"
    # Comparando a branch local com a branch remota para verificar atualização
    local status=$(git -C "$repo_path" rev-list --left-right --count HEAD..."origin/$branch")
    local ahead=$(echo "$status" | awk '{print $1}')
    local behind=$(echo "$status" | awk '{print $2}')

    if [ $behind -gt 0 ]; then
        echo_warning "Há uma atualização disponível na branch $branch para o repositório em $repo_path."
        read -p "Pressione Enter para atualizar ou Ctrl+C para cancelar..."

        # Realiza o pull para atualizar
        git -C "$repo_path" pull "$repo_url" "$branch"
        echo "Atualização concluída com sucesso em $repo_path."
    else
        echo_info "A versão do utilitário "\sdocker"\ é a mais recente dispónível."
    fi

    # Atualiza o arquivo de controle com a data de hoje
    echo "$today" > "$check_file"
}


