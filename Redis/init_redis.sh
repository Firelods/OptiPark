#!/bin/bash

# Script d'initialisation Redis - Filtre les commentaires et gère les lignes de continuation

echo "🔄 Initialisation de Redis avec le script init_parking.redis..."

# Attendre que Redis soit prêt
until redis-cli -h redis ping > /dev/null 2>&1; do
  echo "⏳ Attente de Redis..."
  sleep 1
done

echo "✅ Redis est prêt, exécution du script d'initialisation..."

# Traiter le fichier :
# 1. Supprimer les commentaires (lignes commençant par #)
# 2. Joindre les lignes avec backslash (continuation)
# 3. Supprimer les lignes vides
# 4. Exécuter chaque commande dans Redis

# Créer un fichier temporaire sans commentaires et avec lignes jointes
sed 's/#.*//' /scripts/init_parking.redis | \
  sed ':a;/\\$/{N;s/\\\n/ /;ta}' | \
  grep -v '^[[:space:]]*$' > /tmp/redis_commands.txt

# Exécuter ligne par ligne
while IFS= read -r line; do
  echo "$line" | redis-cli -h redis > /dev/null
  if [ $? -ne 0 ]; then
    echo "❌ Erreur lors de l'exécution de: $line"
  fi
done < /tmp/redis_commands.txt

# Nettoyer
rm /tmp/redis_commands.txt

echo "✅ Script d'initialisation exécuté avec succès !"

# Vérifier le nombre de clés créées
KEYS_COUNT=$(redis-cli -h redis DBSIZE)
echo "📊 $KEYS_COUNT"

# Vérifier quelques clés
echo "🔍 Exemples de clés créées:"
redis-cli -h redis KEYS "spot:A-*" | head -5
