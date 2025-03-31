#!/bin/bash

# Carregando dependências
source "$(dirname "${BASH_SOURCE[0]}")/docker_network_utils.sh"

function tratar_erro_pool_sobreposto() {
    local _service_name="$1"
    local _option="${*:2}"

    echo_debug "args: $@"

    if [ -z "$DOCKER_IPAM_CONFIG_SUBNET" ]; then
        echo_error "A variável DOCKER_IPAM_CONFIG_SUBNET não está definida."
        echo_debug "return: 1"
        return 1
    fi

    local resultado_conflito sucesso=0
    resultado_conflito=$(verificar_sobreposicao_subrede "$DOCKER_IPAM_CONFIG_SUBNET")
    local _return_func=$?

    if [ $_return_func -eq 0 ]; then
        # Docker acusou erro, mas heurísticas não encontraram conflito
        echo_warning "O Docker relatou um conflito de sub-rede, mas não foi possível identificar a origem com as heurísticas atuais."
    else
        local tipo_conflito origem_conflito
        tipo_conflito=$(echo "$resultado_conflito" | awk '{print $1}')
        origem_conflito=$(echo "$resultado_conflito" | cut -d' ' -f2-)

        echo_warning "A sub-rede '$DOCKER_IPAM_CONFIG_SUBNET' entra em conflito com a rede '$tipo_conflito $origem_conflito'."
    fi

    echo_info "Sugerindo sub-rede alternativa..."

    local resultado subrede ip_sugerido

##    resultado=$(encontrar_subrede_disponivel "$(echo "$DOCKER_IPAM_CONFIG_SUBNET" | cut -d'.' -f1-2).0.0" 24 100)
##    if [[ $? -ne 0 ]]; then
##
##    fi
    resultado=$(determinar_docker_ipam_config)
    if [ $? -eq 0 ]; then
        subrede=$(echo "$resultado" | awk '{print $1}')
        ip_sugerido=$(echo "$resultado" | awk '{print $2}')
        echo_success "Use essas configurações no arquivo .env:
        \"DOCKER_IPAM_CONFIG_SUBNET=$nova_subrede\"
        \"DOCKER_IPAM_CONFIG_GATEWAY_IP=$novo_gateway\"
        "
    else
        sucesso=1
        echo_error "Não foi possível sugerir uma sub-rede segura automaticamente."
    fi

    echo_debug "return: $sucesso"
    return $sucesso
}

function tratar_erro_porta_ocupada() {
    ##
    # Trata erro de porta já alocada durante inicialização de container Docker.
    #
    # Detecta a porta em uso a partir da mensagem de erro e oferece ao usuário a
    # opção de encerrar o container que está ocupando a porta.
    #
    # Parâmetros:
    #   $1 - Mensagem de erro retornada pelo Docker (contendo o erro da porta)
    #
    # Retorno:
    #   0 - Se o serviço foi encerrado com sucesso
    #   1 - Se o usuário optou por não encerrar ou falha na interrupção
    #
    # Exemplo de uso:
    #   tratar_erro_porta_ocupada "$stderr"

    local error_message="$1"
    echo_debug "args:> $@"

    local port
    local service

    port=$(echo "$error_message" | grep -oP '0\.0\.0\.0:\K[0-9]+')

    if [[ -z "$port" ]]; then
        echo_error "Porta não identificada na mensagem de erro."
        return 1
    fi

    service=$(docker ps --filter "publish=${port}" --format "{{.Names}}")

    echo_warning "
A porta $port já está em uso. O Docker não conseguiu vincular outra instância.
Soluções possíveis:
1. Altere a porta no arquivo .env
2. Encerre o serviço que está usando a porta atual."

    if [ -n "$service" ]; then
        echo_info "Serviço detectado na porta $port: $service"
        read -r -p "Deseja encerrar esse serviço? Pressione 'S' para confirmar ou [ENTER] para ignorar: " resposta
        resposta=$(echo "$resposta" | tr '[:lower:]' '[:upper:]')
        if [ "$resposta" = "S" ]; then
            echo ">>> docker stop $service"
            if docker stop "$service"; then
                echo_success "-- Serviço $service encerrado com sucesso."
                echo_debug "return: 0"
                return 0
            else
                echo_error "-- Falha ao encerrar o serviço $service."
            fi
        fi
    else
        echo_info "Nenhum container Docker conhecido usando a porta $port foi identificado."
    fi
    echo_debug "return: 1"
    return 1
}

function oferecer_remocao_rede_docker() {
    ##
    # Oferece ao usuário a opção de remover uma rede Docker existente.
    #
    # Parâmetros:
    #   $1 - Nome da rede Docker a ser removida
    #
    # Retorno:
    #   0 - Se a rede foi removida com sucesso
    #   1 - Se o usuário optou por não remover ou a remoção falhou
    #
    # Exemplo de uso:
    #   oferecer_remocao_rede_docker "minha_rede_customizada"

    local nome_rede="$1"

    read -r -p "Deseja remover a rede \"$nome_rede\"? Pressione 'S' para confirmar ou [ENTER] para ignorar: " resposta
    resposta=$(echo "$resposta" | tr '[:lower:]' '[:upper:]')

    if [ "$resposta" = "S" ]; then
        echo ">>> docker network rm $nome_rede"
        if docker network rm "$nome_rede"; then
            echo_success "-- Rede \"$nome_rede\" removida com sucesso."
            return 0
        else
            echo_error "-- Falha ao remover a rede \"$nome_rede\"."
            return 1
        fi
    else
        echo_error "-- A rede \"$nome_rede\" não foi removida."
        return 1
    fi
}

function sugerir_nova_subrede() {
    # Sugere uma sub-rede segura fora das faixas padrões (172.30.0.0/24)
    sugerir_subrede_disponivel "172.30.0.0" 24 100
}

function handle_container_init_failure() {
    ##
    # Trata falhas de inicialização de containers Docker.
    #
    # Esta função analisa a mensagem de erro gerada pelo `docker compose` e tenta aplicar correções
    # conhecidas para os seguintes casos:
    #   1. Sobreposição de sub-rede (ex: "invalid pool request")
    #   2. Porta já alocada (ex: "port is already allocated")
    #
    # Parâmetros:
    #   $1 - Mensagem de erro (string com conteúdo de stderr)
    #   $2 - Nome do serviço Docker afetado (ex: vpn)
    #   $3+ - Argumentos extras que serão repassados aos comandos de tratamento
    #
    # Retorno:
    #   0 - Se o erro foi tratado com sucesso
    #   1 - Se o erro não foi tratado ou não foi identificado
    #
    # Exemplo de uso:
    #   if ! docker compose up -d vpn 2>err.log; then
    #       handle_container_init_failure "$(cat err.log)" "vpn"
    #   fi
    #  docker network inspect $(docker network ls -q) --format '{{json .Name}} {{range .IPAM.Config}}{{.Subnet}}{{end}}' | grep "$(echo $DOCKER_VPN_IP | cut -d'.' -f1-3)"

    local exit_code=$?
    local error_message="$1"
    local _service_name="$2"
    local _option="${*:3}"

    echo_debug "args: $@"
    echo_debug "
      exit_code=$exit_code
      error_message=$error_message
      _service_name=$_service_name
      _option=$_option
    "

    local sucesso=0

    if echo "$error_message" | grep -iq "no such file or directory"; then
        service_stop "$_service_name" $_option
        echo_debug "return: 1"
        return 1
    fi

    if [ $exit_code -ne 0 ] || echo "$error_message" | grep -iq "error"; then
        echo_error "Falha ao inicializar o container:
$error_message"

        echo "Aguarde enquanto analisamos uma solução ..."

        if echo "$error_message" | grep -iq "invalid pool request"; then
            tratar_erro_pool_sobreposto "$_service_name" "$_option"
            sucesso=$?
        elif echo "$error_message" | grep -iq "port is already allocated"; then
            tratar_erro_porta_ocupada "$error_message"
            sucesso=$?
        else
          echo_warning "Erro \"$error_message\" não tratado."
        fi

        service_stop "$_service_name" $_option
        echo_debug "return: $sucesso"
        return $sucesso
    fi

    echo_debug "return: 0"
    return 0
}

