# Documentation de Déploiement OptiPark

Guide complet pour lancer l'infrastructure OptiPark avec Docker Compose.

## Table des Matières

- [Vue d'ensemble](#vue-densemble)
- [Prérequis](#prérequis)
- [Configuration](#configuration)
- [Lancement](#lancement)
- [Vérification](#vérification)
- [Interfaces disponibles](#interfaces-disponibles)
- [Architecture des services](#architecture-des-services)
- [Guide de test](#guide-de-test)
- [Troubleshooting](#troubleshooting)
- [Arrêt et nettoyage](#arrêt-et-nettoyage)

---

## Vue d'ensemble

OptiPark est une plateforme de gestion intelligente de parkings basée sur une architecture événementielle avec Kafka. Le système collecte les données des capteurs ESP32 via MQTT, les traite avec Kafka et stocke les états dans Redis pour un accès rapide via une API REST et une application web.

### Architecture globale

```
ESP32 (Capteurs)
    ↓ MQTT
Mosquitto (Broker MQTT)
    ↓
MQTT-Kafka Bridge
    ↓ Kafka
Topics Kafka (parking.nice_sophia.A/B/C)
    ↓
[Parking-Redis-Writer] → Redis ← [Controle-Reservation]
                          ↓
                    API Reservation
                          ↓
                    Application Web
```

---

## Prérequis

### Logiciels requis

- Docker (version 20.10+)
- Docker Compose (version 2.0+)
- Git (pour cloner le repository)

### Ressources système minimales

- RAM: 4 GB minimum, 8 GB recommandé
- Disque: 5 GB d'espace libre
- CPU: 2 cores minimum

### Ports requis

Assurez-vous que les ports suivants sont disponibles:

| Port | Service |
|------|---------|
| 1883 | Mosquitto (MQTT) |
| 2181 | Zookeeper |
| 3000 | Application Web |
| 3001 | Grafana |
| 6379 | Redis |
| 8000 | API Reservation |
| 8001 | Redis Insight (UI) |
| 8080 | Kafka UI |
| 8081 | Schema Registry |
| 9092 | Kafka Broker |

---

## Configuration

### 1. Fichier d'environnement

Créez un fichier `.env` à la racine du projet à partir du template:

```bash
cp .env.example .env
```

Éditez le fichier `.env` et renseignez les valeurs Supabase:

```bash
VITE_SUPABASE_URL=https://votre-projet.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=votre_cle_publique_supabase
```

**Note**: Ces variables sont utilisées pour l'authentification de l'application web frontend.

### 2. Configuration Firebase (Controle-Reservation)

Le service `controle-reservation` nécessite un fichier de credentials Firebase:

1. Téléchargez le fichier `serviceAccount.json` depuis la console Firebase
2. Placez-le dans `controle-reservation/firebase/serviceAccount.json`

```bash
# Structure attendue:
controle-reservation/
  firebase/
    serviceAccount.json
```

### 3. Configuration Mosquitto (Optionnel)

Le fichier de configuration MQTT se trouve dans `mosquitto/config/mosquitto.conf`.
La configuration par défaut devrait fonctionner pour la plupart des cas.

---

## Lancement

### Démarrage complet

Lancez tous les services avec une seule commande:

```bash
docker-compose up -d
```

Cette commande va:
1. Démarrer Zookeeper et Kafka
2. Créer les topics Kafka automatiquement
3. Initialiser Redis avec les données de parking
4. Enregistrer les schémas dans le Schema Registry
5. Démarrer tous les services applicatifs

### Suivre les logs

Pour voir les logs de tous les services:

```bash
docker-compose logs -f
```

Pour suivre un service spécifique:

```bash
docker-compose logs -f <service-name>

# Exemples:
docker-compose logs -f kafka
docker-compose logs -f mqtt-kafka-bridge
docker-compose logs -f application-web
```

### Démarrage sélectif

Pour démarrer uniquement certains services:

```bash
# Infrastructure de base (Kafka + Redis)
docker-compose up -d zookeeper kafka redis schema-registry

# Ajouter l'API et l'application web
docker-compose up -d reservation application-web

# Ajouter le bridge MQTT
docker-compose up -d mosquitto mqtt-kafka-bridge
```

---

## Vérification

### 1. Vérifier que tous les conteneurs sont démarrés

```bash
docker-compose ps
```

Tous les services devraient être dans l'état `Up` (sauf `kafka-init`, `schema-init` et `redis-init` qui se terminent après initialisation).

### 2. Vérifier Kafka

```bash
# Lister les topics
docker-compose exec kafka kafka-topics --list --bootstrap-server localhost:9092

# Topics attendus:
# - parking.nice_sophia.A
# - parking.nice_sophia.B
# - parking.nice_sophia.C
# - rain.global
```

### 3. Vérifier Redis

```bash
# Vérifier le nombre de clés (environ 60 places de parking)
docker-compose exec redis redis-cli DBSIZE

# Lister les places du parking A
docker-compose exec redis redis-cli KEYS "spot:A-*"

# Afficher les détails d'une place
docker-compose exec redis redis-cli HGETALL spot:A-1
```

### 4. Vérifier l'API Reservation

```bash
curl http://localhost:8000/health
# Devrait retourner: {"status":"healthy"}
```

### 5. Vérifier les logs d'initialisation

```bash
# Redis
docker logs redis-init

# Kafka Topics
docker logs kafka-init

# Schema Registry
docker logs schema-init
```

---

## Interfaces disponibles

Une fois tous les services démarrés, accédez aux interfaces web:

| Interface | URL | Identifiants |
|-----------|-----|--------------|
| **Application Web** | http://localhost:3000 | Authentification Supabase |
| **Kafka UI** | http://localhost:8080 | Aucun |
| **Redis Insight** | http://localhost:8001 | Aucun |
| **Grafana** | http://localhost:3001 | admin / admin |
| **API Reservation** | http://localhost:8000 | API REST publique |
| **Schema Registry** | http://localhost:8081 | API REST |

### Kafka UI

Interface de monitoring Kafka permettant de:
- Visualiser les topics et leurs messages
- Voir les schémas enregistrés
- Monitorer les consumer groups
- Analyser les performances

### Redis Insight

Interface web pour explorer Redis:
- Visualiser toutes les clés
- Inspecter les structures de données
- Exécuter des commandes Redis
- Monitorer les performances

### Grafana

Dashboards de monitoring (en développement):
- Statistiques en temps réel
- Taux d'occupation des parkings
- Métriques système

---

## Architecture des services

### Services d'infrastructure

#### Zookeeper
- **Rôle**: Coordination du cluster Kafka
- **Port**: 2181
- **Dépendances**: Aucune

#### Kafka
- **Rôle**: Broker de messages événementiels
- **Port**: 9092
- **Dépendances**: Zookeeper
- **Configuration**: 3 partitions par topic, replication factor 1

#### Schema Registry
- **Rôle**: Validation et versioning des schémas JSON
- **Port**: 8081
- **Dépendances**: Kafka

#### Redis
- **Rôle**: Base de données en mémoire pour l'état en temps réel
- **Ports**: 6379 (Redis), 8001 (Redis Insight)
- **Volumes**: Persistance des données

### Services de communication

#### Mosquitto
- **Rôle**: Broker MQTT pour les ESP32
- **Port**: 1883
- **Configuration**: `mosquitto/config/mosquitto.conf`

#### MQTT-Kafka Bridge
- **Rôle**: Pont entre MQTT et Kafka
- **Langage**: Node.js
- **Topics MQTT écoutés**: `parking/+/status`
- **Topics Kafka produits**: `parking.<parking_id>`

### Services métier

#### Parking-Redis-Writer
- **Rôle**: Consomme les événements Kafka et met à jour Redis
- **Langage**: Node.js
- **Kafka Consumer Group**: `parking-redis-writer`
- **Topics consommés**: `parking.nice_sophia.A/B/C`

#### Controle-Reservation
- **Rôle**: Gestion des réservations et contrôle d'accès
- **Langage**: Node.js
- **Dépendances**: Firebase, Kafka, Redis

#### Reservation API
- **Rôle**: API REST pour les réservations
- **Langage**: Python (Flask)
- **Port**: 8000
- **Endpoints principaux**:
  - `GET /health` - Health check
  - `GET /parkings` - Liste des parkings
  - `POST /reservations` - Créer une réservation
  - `GET /reservations/:id` - Détails d'une réservation

#### Application Web
- **Rôle**: Interface utilisateur frontend
- **Framework**: React + Vite
- **Port**: 3000
- **Build**: Production (Nginx)

### Services d'initialisation

Ces services s'exécutent une seule fois au démarrage puis se terminent:

#### kafka-init
- Crée les topics Kafka nécessaires

#### schema-init
- Enregistre les schémas JSON dans le Schema Registry

#### redis-init
- Charge les données initiales des parkings (60 places)

---

## Guide de test

### Test du flux complet MQTT → Kafka → Redis

#### 1. Publier un événement via MQTT

```bash
# Publier un événement de libération de place
docker-compose exec mosquitto mosquitto_pub \
  -t 'parking/nice_sophia.A/status' \
  -m '{
    "parking_id":"nice_sophia.A",
    "slot_id":"A-12",
    "occupied":false,
    "battery_mv":3500,
    "sent_at":"2026-01-13T10:00:00Z"
  }'
```

#### 2. Vérifier dans Kafka

```bash
# Consommer les messages du topic
docker-compose exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic parking.nice_sophia.A \
  --from-beginning \
  --max-messages 1
```

#### 3. Vérifier dans Redis

```bash
# Vérifier que la place A-12 est bien à jour
docker-compose exec redis redis-cli HGETALL spot:A-12

# Résultat attendu:
# 1) "parking_id"
# 2) "nice_sophia.A"
# 3) "status"
# 4) "0"  (0 = libre, 1 = occupé)
# 5) "battery_mv"
# 6) "3500"
```

### Test de l'API Reservation

```bash
# Lister les parkings disponibles
curl http://localhost:8000/parkings

# Obtenir les places d'un parking
curl http://localhost:8000/parkings/A/spots

# Créer une réservation (exemple)
curl -X POST http://localhost:8000/reservations \
  -H "Content-Type: application/json" \
  -d '{
    "parking_id": "A",
    "slot_id": "A-12",
    "user_id": "user123",
    "duration": 3600
  }'
```

### Test avec un ESP32 réel

Si vous avez un ESP32 programmé:

1. Configurez le WiFi et l'adresse du broker MQTT dans le code ESP32
2. Pointez vers `mqtt://<votre-ip>:1883`
3. Publiez sur le topic `parking/<parking_id>/status`
4. Vérifiez les logs: `docker-compose logs -f mqtt-kafka-bridge`

---

## Troubleshooting

### Problème: Les conteneurs ne démarrent pas

```bash
# Vérifier les logs d'erreur
docker-compose logs

# Vérifier que les ports ne sont pas déjà utilisés
netstat -an | grep "1883\|3000\|6379\|8000\|8080\|9092"

# Sur Windows PowerShell:
netstat -an | Select-String "1883|3000|6379|8000|8080|9092"
```

### Problème: Kafka ne démarre pas

```bash
# Vérifier que Zookeeper est bien démarré
docker-compose ps zookeeper

# Vérifier les logs Kafka
docker-compose logs kafka

# Redémarrer Kafka
docker-compose restart kafka
```

### Problème: Redis n'a pas de données

```bash
# Vérifier les logs d'initialisation
docker logs redis-init

# Réinitialiser Redis manuellement
docker-compose up -d redis-init

# Ou vider et recharger
docker-compose exec redis redis-cli FLUSHALL
docker-compose up -d redis-init
```

### Problème: Les topics Kafka ne sont pas créés

```bash
# Vérifier les logs d'initialisation
docker logs kafka-init

# Créer manuellement les topics
docker-compose exec kafka kafka-topics \
  --create --if-not-exists \
  --bootstrap-server localhost:9092 \
  --partitions 3 \
  --replication-factor 1 \
  --topic parking.nice_sophia.A
```

### Problème: MQTT-Kafka Bridge ne fonctionne pas

```bash
# Vérifier les logs
docker-compose logs mqtt-kafka-bridge

# Tester la connexion MQTT
docker-compose exec mosquitto mosquitto_sub -t 'parking/#' -v

# Dans un autre terminal, publier un message de test
docker-compose exec mosquitto mosquitto_pub -t 'parking/test/status' -m 'test'
```

### Problème: L'application web ne charge pas

```bash
# Vérifier que le fichier .env existe et est correct
cat .env

# Vérifier les logs du build
docker-compose logs application-web

# Reconstruire l'image
docker-compose build application-web
docker-compose up -d application-web
```

### Problème: Erreur de permissions (Windows)

Si vous rencontrez des erreurs de permissions sur Windows:

```bash
# Donner les droits d'exécution aux scripts
git update-index --chmod=+x Redis/init_redis_fixed.sh
git update-index --chmod=+x kafka/scripts/init_registry.sh
```

### Problème: "Cannot connect to Docker daemon"

```bash
# Vérifier que Docker est démarré
docker ps

# Sur Windows, vérifier que Docker Desktop est lancé
```

---

## Arrêt et nettoyage

### Arrêter tous les services

```bash
# Arrêter les conteneurs
docker-compose down

# Arrêter ET supprimer les volumes (⚠️ perte de données)
docker-compose down -v
```

### Nettoyer complètement

```bash
# Supprimer tout (conteneurs, volumes, réseaux, images)
docker-compose down -v --rmi all

# Nettoyer les images Docker non utilisées
docker system prune -a
```

### Redémarrer un service spécifique

```bash
# Redémarrer un service
docker-compose restart <service-name>

# Reconstruire et redémarrer
docker-compose up -d --build <service-name>
```

### Voir l'utilisation des ressources

```bash
# Utilisation CPU/Mémoire par conteneur
docker stats

# Espace disque utilisé par Docker
docker system df
```

---

## Commandes utiles

### Docker Compose

```bash
# Démarrer en mode détaché
docker-compose up -d

# Démarrer avec rebuild des images
docker-compose up -d --build

# Voir les conteneurs en cours
docker-compose ps

# Voir tous les logs
docker-compose logs -f

# Logs d'un service spécifique
docker-compose logs -f <service>

# Exécuter une commande dans un conteneur
docker-compose exec <service> <command>

# Arrêter un service
docker-compose stop <service>

# Redémarrer un service
docker-compose restart <service>

# Supprimer les conteneurs arrêtés
docker-compose rm
```

### Kafka

```bash
# Lister les topics
docker-compose exec kafka kafka-topics --list --bootstrap-server localhost:9092

# Décrire un topic
docker-compose exec kafka kafka-topics --describe --bootstrap-server localhost:9092 --topic parking.nice_sophia.A

# Consommer les messages
docker-compose exec kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic parking.nice_sophia.A --from-beginning

# Produire un message
docker-compose exec kafka kafka-console-producer --bootstrap-server localhost:9092 --topic parking.nice_sophia.A
```

### Redis

```bash
# Lancer redis-cli
docker-compose exec redis redis-cli

# Compter les clés
docker-compose exec redis redis-cli DBSIZE

# Chercher des clés
docker-compose exec redis redis-cli KEYS "spot:*"

# Lire un hash
docker-compose exec redis redis-cli HGETALL spot:A-1

# Vider la base (⚠️)
docker-compose exec redis redis-cli FLUSHALL
```

### MQTT

```bash
# S'abonner à tous les topics parking
docker-compose exec mosquitto mosquitto_sub -t 'parking/#' -v

# Publier un message
docker-compose exec mosquitto mosquitto_pub -t 'parking/nice_sophia.A/status' -m '{"slot_id":"A-1","occupied":false}'
```

---

## Structure des données

### Topics Kafka

Le système utilise les topics suivants:

#### parking.nice_sophia.{A|B|C}
Événements des places de parking

**Topics:**
- `parking.nice_sophia.A` - Événements du parking A (3 partitions)
- `parking.nice_sophia.B` - Événements du parking B (3 partitions)
- `parking.nice_sophia.C` - Événements du parking C (3 partitions)

**Format du message:**
```json
{
  "parking_id": "nice_sophia.A",
  "slot_id": "A-12",
  "occupied": false,
  "battery_mv": 3500,
  "sent_at": "2026-01-13T10:00:00Z",
  "received_at": "2026-01-13T10:00:01Z"
}
```

**Champs:**
- `parking_id`: ID complet du parking (ex: "nice_sophia.A")
- `slot_id`: ID de la place (ex: "A-12")
- `occupied`: Booléen - true si occupé, false si libre
- `battery_mv`: (Optionnel) Niveau batterie en millivolts
- `sent_at`: Timestamp ISO 8601 d'envoi par le capteur
- `received_at`: (Optionnel) Timestamp de réception par le bridge

#### rain.global
Événements météo (pluie)

**Topic:** `rain.global` (1 partition)

**Format du message:**
```json
{
  "sensor_id": "WEATHER_SENSOR_01",
  "rain_pct": 35
}
```

**Champs:**
- `sensor_id`: ID du capteur météo
- `rain_pct`: Pourcentage de pluie (0-100)

**Traitement:**
Le service `parking-redis-writer` convertit en 0/1:
- `rain_pct >= 20` → `weather:rain = 1` (pluie)
- `rain_pct < 20` → `weather:rain = 0` (pas de pluie)

### Données Redis

#### Hash: `spot:{slot_id}`
Hash contenant les informations d'une place

```redis
HGETALL spot:A-12
1) "parking_id"
2) "A"                         # Version courte: A, B, ou C
3) "status"
4) "0"                         # 0=libre, 1=occupé, 2=réservé
5) "type"
6) "NORMAL"                    # NORMAL, COVERED, PMR, EV
7) "covered"
8) "0"                         # 0=non couvert, 1=couvert
9) "battery_mv"
10) "3500"
11) "sent_at"
12) "2026-01-13T10:00:00Z"
13) "received_at"
14) "2026-01-13T10:00:01Z"
```

**Note:** Le `parking_id` est automatiquement converti de "nice_sophia.A" → "A" par le service `parking-redis-writer`

#### Set: `parking:{parking_id}:free`
Ensemble des IDs de places **libres** d'un parking

**Note:** Le parking_id utilisé dans Redis est la version courte (A, B, C)

```redis
SMEMBERS parking:A:free
# Retourne: A-1, A-2, A-3, ..., A-20 (uniquement les places libres)
```

**Gestion automatique:**
- Quand `occupied=true` → La place est retirée du set
- Quand `occupied=false` → La place est ajoutée au set

---

## Développement

### Modification d'un service

1. Modifier le code source
2. Reconstruire l'image Docker:
   ```bash
   docker-compose build <service-name>
   ```
3. Redémarrer le service:
   ```bash
   docker-compose up -d <service-name>
   ```

### Ajouter un nouveau topic Kafka

1. Éditer `docker-compose.yml` dans le service `kafka-init`
2. Ajouter la commande de création du topic
3. Redémarrer l'initialisation:
   ```bash
   docker-compose up -d kafka-init
   ```

### Ajouter des données Redis

1. Éditer `Redis/init_parking.redis`
2. Réinitialiser Redis:
   ```bash
   docker-compose exec redis redis-cli FLUSHALL
   docker-compose up -d redis-init
   ```

---

## Support et Contact

- **Issues GitHub**: Pour reporter des bugs ou demander des fonctionnalités
- **Documentation projet**: Voir `README.md` pour plus d'informations
- **Architecture Kafka**: Voir les schémas dans `schemas/`

---

## Licence

Projet OptiPark - Polytech Nice Sophia SI5
