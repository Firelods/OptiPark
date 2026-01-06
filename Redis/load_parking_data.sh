#!/bin/bash

# Script à exécuter manuellement pour charger les données de parking

echo "🔄 Chargement des données de parking dans Redis..."

# Traiter le fichier pour gérer les lignes de continuation
sed 's/#.*//' init_parking.redis | \
  sed ':a;/\\$/{N;s/\\\n/ /;ta}' | \
  grep -v '^[[:space:]]*$' | \
  docker exec -i redis redis-cli > /dev/null

if [ $? -eq 0 ]; then
  echo "✅ Données chargées avec succès !"

  # Afficher quelques statistiques
  echo ""
  echo "📊 Statistiques:"
  docker exec redis redis-cli DBSIZE
  echo ""
  echo "🅰️  Places parking A:"
  docker exec redis redis-cli KEYS "spot:A-*" | wc -l
  echo ""
  echo "🅱️  Places parking B:"
  docker exec redis redis-cli KEYS "spot:B-*" | wc -l
  echo ""
  echo "Exemples de places:"
  docker exec redis redis-cli HGETALL spot:A-1
else
  echo "❌ Erreur lors du chargement des données"
  exit 1
fi
