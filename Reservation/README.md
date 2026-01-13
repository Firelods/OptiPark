# Reservation API

API REST Python (Flask) pour gérer les réservations de places de parking avec algorithme intelligent de sélection.

## Rôle dans l'architecture

Cette API fournit l'interface REST pour les applications (web et mobile) et implémente la logique métier de réservation.

```
Application Web/Mobile
    ↓ HTTP REST
Reservation API (Flask)
    ↓ Lecture/Écriture
Redis (état des places)
```

## Fonctionnalités

### 1. Réservation intelligente de place

Trouve la meilleure place disponible selon plusieurs critères:

**Endpoint:** `POST /reserve`

**Request:**
```json
{
  "block_id": "block_A",
  "user_type": "NORMAL"
}
```

**Paramètres:**
- `block_id`: ID du bloc d'entrée/zone du parking
- `user_type`: Type d'utilisateur (`NORMAL`, `PMR`, `EV`)

**Response (succès):**
```json
{
  "spot_id": "A-12",
  "parking_id": "A",
  "type": "NORMAL",
  "x": 150.5,
  "y": 200.3,
  "status": 2,
  "rain": 0
}
```

**Response (erreur):**
```json
{
  "error": "NO_SPOT_AVAILABLE"
}
```

**Codes d'erreur:**
- `INVALID_BLOCK`: block_id inconnu
- `INVALID_USER_TYPE`: user_type invalide
- `NO_SPOT_AVAILABLE`: Aucune place libre

### 2. Algorithme de sélection

L'algorithme prend en compte:

#### Priorité par type d'utilisateur

| User Type | Priorité 1 | Priorité 2 | Priorité 3 |
|-----------|-----------|-----------|-----------|
| NORMAL | NORMAL | EV | PMR |
| EV | EV | NORMAL | PMR |
| PMR | PMR | NORMAL | EV |

#### Critères de tri

**Sans pluie:**
- Distance à l'entrée (plus proche = mieux)

**Avec pluie:**
1. Places couvertes en priorité
2. Puis distance à l'entrée

#### Exemple

Utilisateur NORMAL, pluie:
```
1. Chercher places NORMAL couvertes → Trier par distance
2. Si aucune → Chercher places NORMAL non couvertes → Trier par distance
3. Si aucune → Chercher places EV couvertes → Trier par distance
4. Etc.
```

### 3. Récupérer toutes les places

**Endpoint:** `GET /get-spots`

**Response:**
```json
{
  "spots": {
    "A-1": {
      "status": 0,
      "type": "NORMAL",
      "parking_id": "A",
      "x": 100.0,
      "y": 150.0
    },
    "A-2": {
      "status": 1,
      "type": "COVERED",
      "parking_id": "A",
      "x": 120.0,
      "y": 150.0
    }
  }
}
```

**Codes de statut:**
- `0`: FREE (libre)
- `1`: OCCUPIED (occupée)
- `2`: RESERVED (réservée)
- `3`: BLOCKED (bloquée)

### 4. Annuler une réservation

**Endpoint:** `POST /cancel-reservation`

**Request:**
```json
{
  "spot_id": "A-12"
}
```

**Response:**
```json
{
  "success": true
}
```

**Action:** Remet le statut de la place à FREE (0)

### 5. Confirmer une réservation

**Endpoint:** `POST /confirm-reservation`

**Request:**
```json
{
  "spot_id": "A-12"
}
```

**Response:**
```json
{
  "success": true
}
```

**Action:** Change le statut de RESERVED (2) à OCCUPIED (1)

### 6. Météo

**Endpoint:** `GET /weather`

**Response:**
```json
{
  "rain": 1
}
```

**Valeurs:**
- `0`: Pas de pluie
- `1`: Pluie détectée

### 7. Health check

**Endpoint:** `GET /health`

**Response:**
```json
{
  "status": "ok"
}
```

## Configuration

### Variables d'environnement

| Variable | Description | Défaut |
|----------|-------------|--------|
| `REDIS_HOST` | Hôte Redis | `redis` |
| `REDIS_PORT` | Port Redis | `6379` |

### Fichiers de configuration

L'API utilise des fichiers JSON statiques dans `config/`:

#### `config/blocks.json`

Définit les blocs/entrées du parking:

```json
{
  "blocks": [
    {
      "id": "block_A",
      "parking_id": "A",
      "name": "Entrée A",
      "description": "Entrée principale parking A"
    }
  ]
}
```

#### `config/spots.json`

Définit les places avec leurs coordonnées:

```json
{
  "spots": [
    {
      "id": "A-1",
      "parking_id": "A",
      "type": "NORMAL",
      "x": 100.0,
      "y": 150.0
    },
    {
      "id": "A-2",
      "parking_id": "A",
      "type": "COVERED",
      "x": 120.0,
      "y": 150.0
    }
  ]
}
```

**Types de places:**
- `NORMAL`: Place standard
- `COVERED`: Place couverte
- `PMR`: Place handicapé
- `EV`: Place avec borne électrique

#### `config/access_points.json`

Définit les points d'entrée pour calculer les distances:

```json
{
  "A": { "x": 0, "y": 0 },
  "B": { "x": 0, "y": 500 },
  "C": { "x": 500, "y": 0 }
}
```

## Installation locale

### Prérequis

- Python 3.9+
- Redis accessible

### Installation

```bash
cd Reservation

# Créer un environnement virtuel
python -m venv venv

# Activer l'environnement (Linux/Mac)
source venv/bin/activate

# Activer l'environnement (Windows)
venv\Scripts\activate

# Installer les dépendances
pip install -r requirements.txt
```

### Configuration

```bash
export REDIS_HOST=localhost
export REDIS_PORT=6379
```

### Démarrage

```bash
python app.py
```

L'API sera accessible sur http://localhost:8000

## Avec Docker

Le service est inclus dans le `docker-compose.yml` principal:

```yaml
reservation:
  build: ./Reservation
  container_name: reservation-api
  depends_on:
    redis:
      condition: service_healthy
  ports:
    - "8000:8000"
  environment:
    REDIS_HOST: redis
    REDIS_PORT: 6379
```

```bash
# Démarrer le service
docker-compose up -d reservation

# Voir les logs
docker-compose logs -f reservation

# Health check
curl http://localhost:8000/health
```

## Dépendances

```txt
flask
flask-cors
redis
```

## Tests avec curl

### Réserver une place

```bash
# Utilisateur normal
curl -X POST http://localhost:8000/reserve \
  -H "Content-Type: application/json" \
  -d '{"block_id":"block_A","user_type":"NORMAL"}'

# Utilisateur PMR
curl -X POST http://localhost:8000/reserve \
  -H "Content-Type: application/json" \
  -d '{"block_id":"block_A","user_type":"PMR"}'

# Véhicule électrique
curl -X POST http://localhost:8000/reserve \
  -H "Content-Type: application/json" \
  -d '{"block_id":"block_A","user_type":"EV"}'
```

### Récupérer toutes les places

```bash
curl http://localhost:8000/get-spots
```

### Annuler une réservation

```bash
curl -X POST http://localhost:8000/cancel-reservation \
  -H "Content-Type: application/json" \
  -d '{"spot_id":"A-12"}'
```

### Confirmer une réservation

```bash
curl -X POST http://localhost:8000/confirm-reservation \
  -H "Content-Type: application/json" \
  -d '{"spot_id":"A-12"}'
```

### Vérifier la météo

```bash
curl http://localhost:8000/weather
```

## Structure du code

```
Reservation/
├── app.py                  # API Flask (routes)
├── reservation_logic.py    # Logique métier
├── requirements.txt        # Dépendances Python
├── Dockerfile             # Image Docker
├── config/
│   ├── blocks.json        # Configuration des blocs
│   ├── spots.json         # Configuration des places
│   └── access_points.json # Points d'entrée
└── README.md              # Ce fichier
```

## Logique métier

### Fonction `find_best_spot(block_id, user_type)`

1. **Validation** du block_id et user_type
2. **Récupération** de l'état météo (pluie ou non)
3. **Pour chaque type de place** (selon priorité):
   - Filtrer les places libres du bon type
   - Calculer la distance à l'entrée
   - Trier selon critères (pluie ou non)
4. **Sélection** de la meilleure place
5. **Réservation** dans Redis
6. **Retour** des informations de la place

### Fonction `distance_spot_access(spot_id, parking_id)`

Calcule la distance euclidienne entre une place et son entrée:

```python
distance = sqrt((spot_x - access_x)² + (spot_y - access_y)²)
```

### Fonction `is_raining()`

Lit la clé Redis `weather:rain`:
- `1` → Pluie
- `0` ou absent → Pas de pluie

## Données Redis

### Lecture

L'API lit depuis Redis:

```redis
# État d'une place
HGETALL spot:A-12
1) "status"
2) "0"           # 0=libre, 1=occupé, 2=réservé
3) "type"
4) "NORMAL"
5) "parking_id"
6) "A"
7) "covered"
8) "0"           # 0=non couvert, 1=couvert

# Météo
GET weather:rain
"1"
```

### Écriture

L'API écrit dans Redis:

```redis
# Réserver une place
HSET spot:A-12 status 2

# Libérer une place
HSET spot:A-12 status 0

# Confirmer occupation
HSET spot:A-12 status 1
```

## CORS

L'API accepte les requêtes de toutes les origines:

```python
CORS(app, resources={r"/*": {"origins": "*"}})
```

En production, il est recommandé de restreindre:

```python
CORS(app, resources={r"/*": {"origins": ["https://app.optipark.com"]}})
```

## Gestion des erreurs

### Erreur 400: Bad Request

Retournée quand un paramètre requis est manquant:

```json
{
  "error": "block_id missing"
}
```

### Erreur 500: Internal Server Error

Si Redis est inaccessible ou autre erreur serveur.

## Performance

- **Temps de réponse**: < 50ms (lecture Redis très rapide)
- **Capacité**: Plusieurs milliers de requêtes/seconde
- **Scalabilité**: Stateless, peut être répliqué horizontalement

## Monitoring

### Health check

```bash
# Vérifier que l'API répond
curl http://localhost:8000/health
```

### Logs

```bash
# Via Docker
docker-compose logs -f reservation

# Via Python
# Les logs Flask s'affichent sur stdout
```

### Métriques

Endpoints à monitorer:
- `/health` → Disponibilité
- `/reserve` → Temps de réponse, taux d'erreur
- `/get-spots` → Volume de données

## Troubleshooting

### L'API ne démarre pas

```bash
# Vérifier les logs
docker-compose logs reservation

# Vérifier que Redis est accessible
docker-compose exec reservation ping redis -c 1
```

### Erreur: "connection refused to redis"

```bash
# Vérifier que Redis est démarré
docker-compose ps redis

# Vérifier la connectivité
docker-compose exec reservation nc -zv redis 6379
```

### Erreur: "FileNotFoundError: config/blocks.json"

Les fichiers de configuration sont manquants. Vérifiez qu'ils existent dans `Reservation/config/`.

### Aucune place n'est disponible

```bash
# Vérifier l'état des places dans Redis
docker-compose exec redis redis-cli KEYS "spot:*"
docker-compose exec redis redis-cli HGETALL spot:A-1

# Réinitialiser Redis
docker-compose up -d redis-init
```

## Intégration

### Services en amont

- **Parking-Redis-Writer**: Met à jour les statuts en temps réel

### Services en aval

- **Application Web**: Interface utilisateur React
- **Application Mobile**: App Flutter
- **Controle-Reservation**: Confirmations via FCM

## Évolutions possibles

1. **Authentification**: JWT ou OAuth2
2. **Base de données**: Historique des réservations (PostgreSQL)
3. **Cache**: Mettre en cache les résultats de `get-spots`
4. **Pagination**: Pour les parkings avec beaucoup de places
5. **WebSocket**: Notifications en temps réel
6. **Analytics**: Tracking des réservations
7. **Rate limiting**: Protection contre les abus
8. **Géolocalisation**: Proposer le parking le plus proche

## API Documentation

Pour une documentation interactive (Swagger/OpenAPI), vous pouvez utiliser Flask-RESTX:

```bash
pip install flask-restx
```

Ou générer une collection Postman (voir `postman/OptiPark_API.postman_collection.json`).

## Licence

Projet OptiPark - Polytech Nice Sophia SI5
