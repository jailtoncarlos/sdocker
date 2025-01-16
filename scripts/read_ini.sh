#!/bin/bash

#Explicação do Funcionamento:
#Parâmetros:
#
#file: O arquivo .ini que será lido.
#section: A seção do arquivo .ini onde se encontra a chave.
#key: A chave dentro da seção que será lida.
#Como funciona:
#
#O comando sed é usado para procurar a seção correta (^\[$section\]).
#Dentro dessa seção, ele continua procurando a chave (^$key[ ]*=).
#Quando a chave é encontrada, o valor é extraído removendo o conteúdo antes do = e exibindo o que vem após o símbolo.
#Detalhes Técnicos:
#
#O sed -nr utiliza a opção -n para não imprimir todas as linhas por padrão, e -r para permitir o uso de expressões regulares extendidas.
#O rótulo :l e o comando b l criam um loop para continuar analisando a linha até encontrar a chave desejada.
#Quando a chave é encontrada, s/.*=[ ]*// remove tudo até o = e p imprime o valor.

# Function to read a value from an ini file
function read_ini() {
    local file=$1
    local section=$2
    local key=$3

    # Usa delimitadores alternativos para evitar conflitos com `/`
    value=$(awk -F= -v section="$section" -v key="$key" '
        $0 ~ "\\[" section "\\]" {in_section=1; next}
        in_section && $0 ~ "^\\[" {in_section=0}
        in_section && $1 ~ key {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}
    ' "$file")

    echo "$value"
}

# Example usage
#user=$(read_ini "config.ini" "database" "user")
#echo "User: $user"


# Função para ler todas as chaves e valores de uma seção e preencher o dicionário passado como argumento
function read_section() {
    local file=$1
    local section=$2
    local -n dict=$3  # Referência ao dicionário passado como argumento

    # Inicializar flag de erro
    local success=1

    # Verifica se o arquivo existe e se a seção especificada está presente
    if [[ -f "$file" ]]; then
        # Extrair todas as chaves e valores da seção especificada
        while IFS='=' read -r key value; do
            # Remover espaços em branco ao redor de key e value
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)

            # Adiciona chave-valor ao dicionário se a linha pertence à seção correta
            if [[ -n "$key" && "$key" != \[*\] ]]; then
                dict["$key"]="$value"
                success=0  # Define flag para indicar sucesso
            fi
        done < <(sed -n "/^\[$section\]/,/^\[/{/^[^[]/p;}" "$file")
    fi

    return $success
}
# Exemplo de uso:
# Declaração do dicionário
#declare -A environment_conditions
#
## Chamada da função para preencher o dicionário com a seção "environment_dev_existence_condition"
#if read_section "config.ini" "environment_dev_existence_condition" environment_conditions; then
#    # Itera sobre o dicionário para exibir as chaves e valores
#    for key in "${!environment_conditions[@]}"; do
#        echo "Chave: $key, Valor: ${environment_conditions[$key]}"
#    done
#else
#    echo "Erro: Seção não encontrada ou arquivo não existe."
#fi


