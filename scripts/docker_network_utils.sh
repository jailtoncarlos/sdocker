#!/bin/bash


##############################################################################
# ARQUIVO: docker_network_utils.sh
# DESCRIÇÃO: Funções utilitárias para gestão e validação de sub-redes e IPs em Docker.
#
# DEPENDÊNCIAS:
#   - util.sh (deve ser carregado antes deste script)
##############################################################################

# Carregando dependências
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

### VALIDAÇÃO E VERIFICAÇÃO DE IP E SUBREDE DOCKER ###
# - verificar_ip_gateway_em_uso
# - verificar_subnet_em_uso

### BUSCA DE IP OU SUBREDE DISPONÍVEL ###
# - encontrar_ip_disponivel
# - determinar_docker_ipam_config

### CONVERSÕES ENTRE IP E CIDR ###
# - ip_to_int
# - cidr_to_range

### VERIFICAÇÃO DE CONFLITOS COM REDES LOCAIS ###
# - verificar_conflito_interfaces_locais
# - verificar_conflito_interfaces_windows

### GERENCIAMENTO DE SUBREDE E SUGESTÃO AUTOMÁTICA ###
# - verificar_sobreposicao_subrede
# - encontrar_subrede_disponivel
# - sugerir_subrede_disponivel

##############################################################################
### VALIDAÇÃO E VERIFICAÇÃO DE IP E SUBREDE DOCKER ###
##############################################################################
function verificar_ip_gateway_em_uso() {
    ##
    # verificar_ip_gateway_em_uso
    #
    # Verifica se um IP específico está sendo utilizado como gateway em alguma rede Docker existente.
    #
    # Parâmetros:
    #   gateway_ip (string): Endereço IP do gateway a ser verificado (ex: "172.30.0.1").
    #
    # Retorno:
    #   0 - Se o IP do gateway já estiver em uso por alguma rede Docker.
    #   1 - Se o IP do gateway não estiver em uso (disponível).
    #
    # Exemplo de uso:
    #   if verificar_ip_gateway_em_uso "172.30.0.1"; then
    #       echo "Gateway em uso."
    #   else
    #       echo "Gateway disponível."
    #   fi
    ##
    local gateway_ip="$1"
    echo_debug "args: $@"

    # Validar que é um IP válido (não CIDR)
    if ! [[ $gateway_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo_error "Informe um IP válido, não um CIDR. Entrada recebida: $gateway_ip"
        echo_debug "return: 2"
        return 2
    fi

    if docker network inspect --format '{{range .IPAM.Config}}{{.Gateway}}{{"\n"}}{{end}}' $(docker network ls -q) | grep -Fxq "$gateway_ip"; then
        echo_debug "IP Gateway $gateway_ip em uso"
        echo_debug "return: 0"
        return 0  # Gateway em uso
    fi
    echo_debug "IP Gateway $gateway_ip disponível"
    echo_debug "return: 1"
    return 1  # Gateway disponível
}

function verificar_subnet_em_uso() {
    ##
    # verificar_subnet_em_uso
    #
    # Verifica se uma sub-rede específica já está sendo usada por redes Docker existentes.
    #
    # Parâmetros:
    #   subnet (string): Sub-rede no formato CIDR a ser verificada (ex: "172.19.0.0/16").
    #
    # Retorno:
    #   1 - Se a sub-rede não estiver em uso.
    #   0 - Se a sub-rede estiver em uso por alguma rede Docker existente.
    #
    # Exemplo de uso:
    #   if verificar_subnet_em_uso "172.19.0.0/16"; then
    #      echo "Sub-rede em uso."
    #   else
    #      echo "Sub-rede disponível."
    #   fi
    ##
    local subnet="$1"
    echo_debug "args: $@"

    local network_id rede_atual

    while read -r network_id; do
        rede_atual=$(docker network inspect "$network_id" --format '{{(index .IPAM.Config 0).Subnet}}')
        if [[ "$rede_atual" == "$subnet" ]]; then
            echo_debug "Sub-rede $subnet está em uso"
            echo_debug "return: 0"
            return 0  # Sub-rede está em uso
        fi
    done < <(docker network ls --filter driver=bridge -q)

    echo_debug "Sub-rede $subnet está disponível"
    echo_debug "return: 1"
    return 1  # Sub-rede está disponível
}

##############################################################################
### BUSCA DE IP OU SUBREDE DISPONÍVEL ###
##############################################################################
function encontrar_ip_disponivel() {
    # no sistema, começando a partir de uma base fornecida (ex: "172.19").
    #
    # A função itera sobre o terceiro octeto (0 a 254) construindo sub-redes e testando:
    #   - Se a sub-rede está em uso (via verificar_subnet_em_uso)
    #   - Se o IP do gateway está em uso (via verificar_ip_gateway_em_uso)
    #
    # Se encontrar uma combinação disponível, retorna:
    #   <subrede_cidr> <gateway_ip>
    #
    # Parâmetros:
    #   $1 - base_ip: os dois primeiros octetos da sub-rede base (ex: "172.19")
    #   $2 - mask: máscara CIDR a ser aplicada (ex: "16")
    #
    # Dependências:
    #   - Funções auxiliares: verificar_subnet_em_uso, verificar_ip_gateway_em_uso
    #
    # Retorno (stdout):
    #   <subrede_cidr> <gateway_ip> (em caso de sucesso)
    #   "Erro: ..." (em caso de falha)
    #
    # Retorno (exit code):
    #   0 - sucesso (sub-rede e gateway disponíveis encontrados)
    #   1 - erro (não encontrou uma combinação disponível)
    #
    # Exemplo de uso:
    #   resultado=$(encontrar_ip_disponivel "172.19" "16")
    #   if [[ $? -eq 0 ]]; then
    #       subrede=$(echo "$resultado" | cut -d ' ' -f 1)
    #       gateway=$(echo "$resultado" | cut -d ' ' -f 2)
    #       echo "Sub-rede disponível: $subrede"
    #       echo "Gateway disponível: $gateway"
    #   else
    #       echo "Nenhuma sub-rede ou IP de gateway disponível foi encontrado."
    #   fi
    local base_ip="$1"  # Ex: "172.19"
    local mask="$2"     # Ex: "16"
    echo_debug "args: $@"

    local terceiro_octeto=0
    # Testar uma série de sub-redes começando no base_ip
    while [ "$terceiro_octeto" -lt 255 ]; do
        # Construir a sub-rede e o IP do gateway
        subnet="${base_ip}.${terceiro_octeto}.0/${mask}"
        gateway_ip="${base_ip}.${terceiro_octeto}.2"

        # Verificar se a sub-rede ou o gateway já estão em uso
        if ! verificar_subnet_em_uso "$subnet" && ! verificar_ip_gateway_em_uso "$gateway_ip"; then
            echo_debug "return: 0, $subnet $gateway_ip"
            echo "$subnet $gateway_ip"
            return 0  # Retornar a sub-rede e o IP do gateway disponíveis
        fi

        # Incrementar o segundo octeto para tentar o próximo intervalo de IP
        terceiro_octeto=$((terceiro_octeto + 1))
    done

    echo "Erro: Nenhuma sub-rede ou IP de gateway disponível encontrado."
    echo_debug "return: 1"
    return 1
}

function determinar_docker_ipam_config() {
    ##
    # Determina automaticamente uma faixa CIDR e um IP de gateway seguros para uso em redes Docker VPN,
    # validando previamente se há conflitos com redes já existentes.
    #
    # Parâmetros:
    #   $1 (opcional) - Faixa CIDR inicial desejada (ex.: "172.19.0.0/16")
    #   $2 (opcional) - IP do gateway inicial desejado (ex.: "172.19.0.2")
    #
    # Caso não fornecidos parâmetros, a função utiliza por padrão a faixa "172.30.0.0/24"
    # e o gateway como "172.30.0.2".
    #
    # Retorno (stdout):
    #   <subrede_cidr> <gateway_ip> (ex.: "172.20.0.0/16 172.20.0.2")
    #
    # Retorno (exit code):
    #   0 - sucesso na identificação ou determinação de uma sub-rede válida
    #   1 - falha em encontrar uma sub-rede segura e disponível
    #
    # Dependências:
    #   - verificar_ip_gateway_em_uso
    #   - verificar_subnet_em_uso
    #   - encontrar_subrede_disponivel
    #
    # Exemplo:
    #   resultado=$(determinar_docker_ipam_config "172.19.0.0/16" "172.19.0.2")
    #   if [ $? -eq 0 ]; then
    #       echo "Configurar VPN com: $resultado"
    #   else
    #       echo "Falha ao determinar rede VPN."
    #   fi
    ##

    local docker_ipam_subnet="${1:-172.30.0.0/24}"
    local docker_ipam_gateway_ip="${2:-172.30.0.1}"

    local base_ip mask conflito=0

    # Extrair base_ip e mask do CIDR fornecido
    IFS='/' read -r base_network mask <<< "$docker_ipam_subnet"
    IFS='.' read -r o1 o2 o3 o4 <<< "$base_network"
    base_ip="${o1}.${o2}"

    echo_debug "args: $@"
    echo_debug "
      docker_ipam_subnet=$docker_ipam_subnet
      docker_ipam_gateway_ip=$docker_ipam_gateway_ip
      base_ip=$base_ip
      mask=$mask
    "

    # Validação de conflito
    if verificar_ip_gateway_em_uso "$docker_ipam_gateway_ip"; then
        conflito=1
        echo_warning "Gateway IP $docker_ipam_gateway_ip já está em uso."
    fi

    if verificar_subnet_em_uso "$docker_ipam_subnet"; then
        conflito=1
        echo_warning "Sub-rede $docker_ipam_subnet já está em uso por outra rede Docker."
    fi

    # Caso haja conflito, buscar nova faixa CIDR e gateway
    if [ "$conflito" -eq 1 ]; then
        echo_info "Procurando uma nova sub-rede segura..."
        local resultado
        resultado=$(encontrar_subrede_disponivel "${base_ip}.0.0" "$mask" 100)
        if [ $? -eq 0 ]; then
            docker_ipam_subnet=$(echo "$resultado" | awk '{print $1}')
            docker_ipam_gateway_ip=$(echo "$resultado" | awk '{print $2}')
            echo_debug "Nova sub-rede encontrada: $docker_ipam_subnet com gateway $docker_ipam_gateway_ip."
        else
            echo_error "Não foi possível encontrar uma sub-rede ou IP de gateway disponível automaticamente."
            echo_debug "return: 1"
            return 1
        fi
    else
        echo_debug "Sub-rede inicial válida: $docker_ipam_subnet com gateway $docker_ipam_gateway_ip."
    fi

    # Retorno final
    echo_debug "return: 0, $docker_ipam_subnet $docker_ipam_gateway_ip"

    echo "$docker_ipam_subnet $docker_ipam_gateway_ip"
    return 0
}


##############################################################################
### CONVERSÕES ENTRE IP E CIDR ###
##############################################################################
function ip_to_int() {
    # Converte um endereço IP no formato decimal pontuado para um número inteiro.
    #
    # Parâmetros:
    #   $1 - IP no formato 192.168.0.1
    #
    # Retorno:
    #   Número inteiro correspondente ao IP (ex: 3232235521)

    local ip="$1"
    echo_debug "args: $@"

    local a b c d
    IFS=. read -r a b c d <<< "$ip"
    numero=$(( (a << 24) + (b << 16) + (c << 8) + d ))
    echo_debug "return: $numero"
    echo $numero
}

function cidr_to_range() {
    # Converte uma sub-rede CIDR para um intervalo de IPs representado em inteiros.
    #
    # Parâmetros:
    #   $1 - Sub-rede no formato CIDR (ex: 192.168.0.0/24)
    #
    # Retorno:
    #   Dois inteiros: IP inicial e IP final da sub-rede

    local cidr="$1"
    echo_debug "args: $@"

    local ip mask
    IFS=/ read -r ip mask <<< "$cidr"

    local ip_int=$(ip_to_int "$ip")
    local netmask=$(( 0xFFFFFFFF << (32 - mask) & 0xFFFFFFFF ))
    local network=$(( ip_int & netmask ))
    local broadcast=$(( network | ~netmask & 0xFFFFFFFF ))

    echo_debug "return: $network $broadcast"
    echo "$network $broadcast"
}

##############################################################################
### VERIFICAÇÃO DE CONFLITOS COM REDES LOCAIS ###
##############################################################################
function verificar_conflito_interfaces_locais() {
    ##
    # verificar_conflito_interfaces_locais
    #
    # Verifica se a sub-rede especificada entra em conflito com as sub-redes
    # configuradas nas interfaces locais do sistema operacional (host).
    #
    # Esta função percorre todas as rotas de rede visíveis via comando `ip route`,
    # extrai os prefixos CIDR e verifica se há sobreposição com a sub-rede informada.
    #
    # Parâmetros:
    #   $1 (int) - Endereço IP inicial da sub-rede, convertido para inteiro.
    #   $2 (int) - Endereço IP final da sub-rede, convertido para inteiro.
    #
    # Retorno:
    #   stdout - Imprime uma string indicando o conflito, no formato:
    #            "interface_local (<sub-rede>)", se houver conflito.
    #   return 0 - Se **não** houver conflito com nenhuma sub-rede local.
    #   return 1 - Se uma sub-rede local conflita com a sub-rede fornecida.
    #
    # Exemplo de uso:
    # if ! verificar_conflito_interfaces_locais "$subnet_start" "$subnet_end"; then
    #     echo "Nenhum conflito com interfaces locais."
    # else
    #     echo "Conflito detectado com interfaces locais."
    # fi

    local subnet_start="$1"
    local subnet_end="$2"
    echo_debug "args: $@"

    while read -r host_subnet; do
        if [[ "$host_subnet" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
            read -r rede_start rede_end <<< "$(cidr_to_range "$host_subnet")"
            if [ "$subnet_start" -le "$rede_end" ] && [ "$subnet_end" -ge "$rede_start" ]; then
                echo_debug "return: 1, interface_local ($host_subnet)"
                echo "interface_local ($host_subnet)"
                return 1
            fi
        fi
    done < <(ip route | grep -Eo '([0-9]+\.){3}[0-9]+/[0-9]+')

    echo_debug "return: 0"
    return 0
}

function verificar_conflito_interfaces_windows() {
    local subnet_start="$1"
    local subnet_end="$2"

    echo_debug "args: $@"

    local resultado cidr iface rede_start rede_end

    resultado=$(
        powershell.exe -Command \
        'Get-NetIPAddress -AddressFamily IPv4 | ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)|$($_.InterfaceAlias)" }' |
        tr -d '\r'
    )

    while IFS='|' read -r cidr iface; do
        [[ "$cidr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]] || continue

        read -r rede_start rede_end <<< "$(cidr_to_range "$cidr")"

        # +1 no final da rede do sistema, e -1 no início da faixa Docker
        if (( subnet_start - 1 <= rede_end && subnet_end + 1 >= rede_start )); then
            echo_debug "return: windows $cidr"
            echo "1, windows $cidr"
            return 1
        fi
    done <<< "$resultado"

    echo_debug "return: 0"
    return 0
}

# powershell.exe -Command "Get-NetIPAddress -AddressFamily IPv4 | Format-Table IPAddress,PrefixLength,InterfaceAlias"

##############################################################################
### GERENCIAMENTO DE SUBREDE E SUGESTÃO AUTOMÁTICA ###
##############################################################################
function verificar_sobreposicao_subrede() {
    ##
    # Verifica se há conflito entre a sub-rede fornecida e interfaces de rede do Docker, host local ou Windows (WSL)
    #
    # Esta função detecta sobreposição de IP entre uma sub-rede fornecida e:
    # - redes Docker criadas no sistema
    # - interfaces locais (via ip route)
    # - interfaces Windows, caso esteja executando em WSL
    #
    # Parâmetros:
    #   $1 - Sub-rede no formato CIDR (ex: 192.168.0.0/24)
    #
    # Retorno:
    #   1 - Se houver conflito (sobreposição de sub-rede)
    #   0 - Se não houver conflito
    #
    # Saída:
    #   Em caso de conflito, imprime no stdout o tipo e a origem do conflito: "docker nome_rede", "local interface_local", "windows <sub-rede>"
    #
    # Exemplo de uso:
    #   if verificar_sobreposicao_subrede "192.168.0.0/24"; then
    #       echo "Nenhuma sobreposição de sub-rede foi detectada."
    #   else
    #       resultado=$(verificar_sobreposicao_subrede "192.168.0.0/24")
    #       tipo=$(echo "$resultado" | awk '{print $1}')
    #       origem=$(echo "$resultado" | cut -d' ' -f2-)
    #       echo "Conflito encontrado com tipo: $tipo - origem: $origem"
    #   fi

    local subnet="$1"
    echo_debug "args: $subnet"

    local tipo_origem=""
    local rede_encontrada=""
    local conflito=0

    read -r subnet_start subnet_end <<< "$(cidr_to_range "$subnet")"

    echo_debug "Verificação sub-rede '$subnet' nas redes Docker"
    while read -r network_id; do
        local nome_rede rede_subnet
        nome_rede=$(docker network inspect --format '{{.Name}}' "$network_id")
        rede_subnet=$(docker network inspect --format '{{if (and .IPAM.Config (index .IPAM.Config 0))}}{{(index .IPAM.Config 0).Subnet}}{{end}}' "$network_id")
        if [ -z "$rede_subnet" ]; then continue; fi

        read -r rede_start rede_end <<< "$(cidr_to_range "$rede_subnet")"

#        echo_debug " docker network inspect --format '{{.Name}}' \"$network_id\""
#        echo_debug " docker network inspect --format '{{if (and .IPAM.Config (index .IPAM.Config 0))}}{{(index .IPAM.Config 0).Subnet}}{{end}}' \"$network_id\""
        echo_debug " verificando rede $nome_rede ($rede_subnet), rede_start=$rede_start, rede_end=$rede_end"

        if [ "$subnet_start" -le "$rede_end" ] && [ "$subnet_end" -ge "$rede_start" ]; then
            tipo_origem="docker"
            rede_encontrada="$nome_rede"
            conflito=1
            echo_debug " conflito detectado, $tipo_origem, $rede_encontrada"
            break
        else
          echo_debug " não há sopreposição, verificando próxima rede"
        fi
    done < <(docker network ls -q)

    if [ $conflito -eq 0 ]; then
        echo_debug "Verificação sub-rede '$subnet' nas interfaces locais do sistema"
        rede_encontrada=$(verificar_conflito_interfaces_locais "$subnet_start" "$subnet_end")
        if [ -n "$rede_encontrada" ]; then
            tipo_origem="local"
            conflito=1
        fi
    fi

    if [ $conflito -eq 0 ] && grep -qi microsoft /proc/version; then
        echo_debug "Verificação sub-rede '$subnet' via PowerShell (Windows, se estiver no WSL)"
        rede_encontrada=$(verificar_conflito_interfaces_windows "$subnet_start" "$subnet_end")
        if [ -n "$rede_encontrada" ]; then
            tipo_origem="windows"
            conflito=1
        fi
    fi

    if [ $conflito -eq 1 ]; then
        echo_debug "Conflito detectado"
        echo_debug "return: 1, $tipo_origem $rede_encontrada"
        echo "$tipo_origem $rede_encontrada"
        return 1
    fi

    echo_debug "Sub-rede '$subnet' disponível."
    echo_debug "return: 0"
    return 0
}

function encontrar_subrede_disponivel() {
    ##
    # Procura por uma sub-rede livre dentro de um intervalo a partir de uma base CIDR.
    #
    # A função adapta-se para diferentes máscaras CIDR (ex: /16, /24, /20), incrementando corretamente os octetos.
    #
    # Parâmetros:
    #   $1 - Base da sub-rede (ex: "192.168.0.0")
    #   $2 - Tamanho do prefixo CIDR (ex: 24)
    #   $3 - Número máximo de sub-redes a testar (ex: 100)
    #
    # Retorno:
    #   0 - Se encontrar sub-rede livre, imprime "<subrede_disponivel> <ip_sugerido>"
    #   1 - Se não encontrar nenhuma sub-rede livre, imprime "<tipo_conflito> <origem_conflito>"
    ##

    local cidr_base="$1"
    local cidr_range="$2"
    local max_subnets="$3"
    echo_debug "args: $@"

    local subnet_disponivel=""
    local ip_sugerido=""
    local tipo=""
    local origem=""

    # Determinar qual octeto incrementar baseado no CIDR
    local increment_octet
    if [ "$cidr_range" -le 8 ]; then
        increment_octet=1
    elif [ "$cidr_range" -le 16 ]; then
        increment_octet=2
    elif [ "$cidr_range" -le 24 ]; then
        increment_octet=3
    else
        increment_octet=4
    fi

    for i in $(seq 0 $((max_subnets - 1))); do
        local subnet
        IFS='.' read -r o1 o2 o3 o4 <<< "$cidr_base"
        case "$increment_octet" in
            1) subnet="$((o1+i)).0.0.0/$cidr_range"; ip_sugerido="$((o1+i)).0.0.2" ;;
            2) subnet="$o1.$((o2+i)).0.0/$cidr_range"; ip_sugerido="$o1.$((o2+i)).0.2" ;;
            3) subnet="$o1.$o2.$((o3+i)).0/$cidr_range"; ip_sugerido="$o1.$o2.$((o3+i)).2" ;;
            4) subnet="$o1.$o2.$o3.$((o4+i*16))/$cidr_range"; ip_sugerido="$o1.$o2.$o3.$((o4+i*16+1))" ;;
        esac

        local resultado_conflito
        resultado_conflito=$(verificar_sobreposicao_subrede "$subnet")

        if [ $? -eq 0 ]; then
            subnet_disponivel="$subnet"
            echo_debug "return: 0, $subnet_disponivel $ip_sugerido"
            echo "$subnet_disponivel $ip_sugerido"
            return 0
        else
            tipo=$(echo "$resultado_conflito" | awk '{print $1}')
            origem=$(echo "$resultado_conflito" | cut -d' ' -f2-)
        fi
    done

    echo "$tipo $origem"
    echo_debug "return: 1, $tipo $origem"
    return 1
}


function sugerir_subrede_disponivel() {
    ##
    # Sugere uma sub-rede livre e um IP de gateway com base em uma faixa inicial.
    #
    # A função gera sub-redes consecutivas automaticamente com base no prefixo CIDR fornecido,
    # adaptando-se para diferentes máscaras (ex.: /16, /24).
    #
    # Parâmetros:
    #   $1 - Base da sub-rede inicial (ex.: "172.19.0.0")
    #   $2 - Prefixo CIDR desejado (ex.: 16 ou 24)
    #   $3 - Número máximo de sub-redes a tentar (ex.: 100)
    #
    # Retorno:
    #   0 - Se encontrar sub-rede livre (saída "<subrede_cidr> <gateway_ip>")
    #   1 - Se não encontrar nenhuma sub-rede livre
    #
    # Exemplo:
    #   sugerir_subrede_disponivel "172.19.0.0" 16 50
    ##

    local base="$1"
    local cidr="$2"
    local max="$3"

    echo_debug "args: $@"

    # Determinar qual octeto incrementar baseado no CIDR
    local increment_octet
    if [ "$cidr" -le 8 ]; then
        increment_octet=1
    elif [ "$cidr" -le 16 ]; then
        increment_octet=2
    elif [ "$cidr" -le 24 ]; then
        increment_octet=3
    else
        increment_octet=4
    fi

    # Loop para testar sub-redes
    for i in $(seq 0 $((max - 1))); do
        local subnet gateway_sugerido

        # Gerar sub-rede dinamicamente conforme máscara CIDR
        IFS='.' read -r o1 o2 o3 o4 <<< "$base"
        case "$increment_octet" in
            1) subnet="$((o1+i)).0.0.0/$cidr"; gateway_sugerido="$((o1+i)).0.0.2" ;;
            2) subnet="$o1.$((o2+i)).0.0/$cidr"; gateway_sugerido="$o1.$((o2+i)).0.2" ;;
            3) subnet="$o1.$o2.$((o3+i)).0/$cidr"; gateway_sugerido="$o1.$o2.$((o3+i)).2" ;;
            4) subnet="$o1.$o2.$o3.$((o4+i*16))/$cidr"; gateway_sugerido="$o1.$o2.$o3.$((o4+i*16+1))" ;;
        esac

        local resultado
        resultado=$(verificar_sobreposicao_subrede "$subnet")

        if [ $? -eq 0 ]; then
            echo_debug "return: 0, $subnet $gateway_sugerido"
            echo "$subnet $gateway_sugerido"
            return 0
        fi
    done

    echo_debug "return: 1, nenhuma sub-rede disponível"
    return 1
}

##############################################################################
# Executa diretamente caso o arquivo seja chamado com argumentos específicos #
##############################################################################

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Exemplo: ./docker_network_utils.sh verificar_gateway_em_uso 172.19.0.2
    funcao="$1"
    shift
    if declare -f "$funcao" > /dev/null; then
        "$funcao" "$@"
        exit $?
    else
        echo "Função '$funcao' não encontrada."
        exit 1
    fi
fi