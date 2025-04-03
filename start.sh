#!/bin/bash

# Carregar variáveis de ambiente
source .env

# Iniciar o servidor Rails
bundle exec rails server -p 3000 -b 0.0.0.0 &

# Iniciar o Sidekiq (worker)
bundle exec sidekiq &

# Iniciar o Vite
yarn dev &

# Aguardar todos os processos
wait 