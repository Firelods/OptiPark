# Collections Postman OptiPark

Ce dossier contient les collections Postman pour tester l'API OptiPark sans avoir besoin de l'application mobile.

## Fichiers

### `OptiPark_API.postman_collection.json`

Collection complète avec tous les endpoints de l'API:
- Health check et météo
- Récupération des places
- Réservations (Normal, PMR, EV)
- Confirmation et annulation
- Scénarios de test complets

### `OptiPark_Local.postman_environment.json`

Environnement pré-configuré pour l'utilisation locale:
- Base URL: `http://localhost:8000`
- Variables automatiques pour les IDs de places réservées

## Installation

### 1. Importer dans Postman

#### Via l'application Postman Desktop

1. Ouvrir Postman
2. Cliquer sur "Import" (en haut à gauche)
3. Glisser-déposer les deux fichiers JSON
4. Ou cliquer sur "files" et sélectionner:
   - `OptiPark_API.postman_collection.json`
   - `OptiPark_Local.postman_environment.json`

#### Via Postman Web

1. Se connecter sur https://web.postman.co
2. Cliquer sur "Import"
3. Uploader les fichiers JSON

### 2. Sélectionner l'environnement

1. Dans le coin supérieur droit, cliquer sur le menu déroulant des environnements
2. Sélectionner "OptiPark Local"
3. Vérifier que `base_url` est bien `http://localhost:8000`

### 3. Démarrer l'API

Assurez-vous que l'API OptiPark est démarrée:

```bash
# Avec Docker Compose
docker-compose up -d reservation

# Vérifier que l'API répond
curl http://localhost:8000/health
```

## Utilisation

### Requêtes individuelles

#### 1. Health Check

```
GET {{base_url}}/health
```

Vérifie que l'API est en ligne.

#### 2. Récupérer toutes les places

```
GET {{base_url}}/get-spots
```

Retourne la liste complète des places avec leur statut:
- `0`: FREE (libre)
- `1`: OCCUPIED (occupée)
- `2`: RESERVED (réservée)

#### 3. Vérifier la météo

```
GET {{base_url}}/weather
```

Retourne:
- `"rain": 0` → Pas de pluie
- `"rain": 1` → Il pleut

#### 4. Réserver une place

```
POST {{base_url}}/reserve
Content-Type: application/json

{
  "block_id": "block_A",
  "user_type": "NORMAL"
}
```

**Types d'utilisateurs disponibles:**
- `NORMAL`: Utilisateur standard
- `PMR`: Personne à Mobilité Réduite
- `EV`: Véhicule électrique

**Blocks disponibles:**
- `block_A`: Parking A
- `block_B`: Parking B
- `block_C`: Parking C

**Réponse:**
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

L'ID de la place (`spot_id`) est automatiquement sauvegardé dans la variable `reserved_spot_id`.

#### 5. Confirmer une réservation

```
POST {{base_url}}/confirm-reservation
Content-Type: application/json

{
  "spot_id": "{{reserved_spot_id}}"
}
```

Change le statut de la place de RESERVED (2) à OCCUPIED (1).

#### 6. Annuler une réservation

```
POST {{base_url}}/cancel-reservation
Content-Type: application/json

{
  "spot_id": "{{reserved_spot_id}}"
}
```

Remet le statut de la place à FREE (0).

### Scénarios de test

La collection inclut 3 scénarios complets que vous pouvez exécuter d'un coup:

#### Scenario 1: Full Reservation Flow

Teste le flux complet:
1. Health check
2. Vérification météo
3. Récupération des places disponibles
4. Réservation d'une place
5. Vérification que la place est réservée
6. Confirmation d'arrivée

**Exécution:**
1. Ouvrir le dossier "Test Scenarios" → "Scenario 1: Full Reservation Flow"
2. Clic droit sur le dossier
3. Sélectionner "Run folder"

#### Scenario 2: Cancel Reservation

Teste l'annulation:
1. Réservation d'une place
2. Annulation de la réservation
3. Vérification que la place est libre

#### Scenario 3: Multiple User Types

Teste les différents types d'utilisateurs:
1. Réservation utilisateur NORMAL
2. Réservation utilisateur PMR
3. Réservation utilisateur EV

## Variables automatiques

Les requêtes de réservation sauvegardent automatiquement les IDs de places dans des variables:

| Variable | Description |
|----------|-------------|
| `reserved_spot_id` | Dernière place réservée (Normal) |
| `reserved_spot_pmr` | Dernière place PMR réservée |
| `reserved_spot_ev` | Dernière place EV réservée |
| `test_spot_id` | Place du scénario de test 1 |
| `cancel_test_spot` | Place du scénario d'annulation |

Ces variables sont utilisées automatiquement par les requêtes de confirmation/annulation.

## Tests automatiques

Certaines requêtes incluent des tests automatiques qui vérifient:
- Les codes de statut HTTP
- La présence des champs requis
- Les valeurs attendues

Pour voir les résultats des tests:
1. Exécuter une requête
2. Regarder l'onglet "Test Results" en bas

Exemple de test pour la réservation:
```javascript
pm.test('Spot reserved successfully', function() {
    pm.expect(jsonData).to.have.property('spot_id');
    pm.expect(jsonData.status).to.equal(2);
});
```

## Workflow typique

### Pour émuler l'application mobile

1. **Démarrer une session utilisateur**

```
GET /get-spots  # Voir les places disponibles
GET /weather    # Vérifier la météo
```

2. **Réserver une place**

```
POST /reserve
{
  "block_id": "block_A",
  "user_type": "NORMAL"
}
# → Sauvegarde automatique du spot_id
```

3. **L'utilisateur arrive sur place**

```
# Simuler la détection ESP32 (via MQTT)
docker-compose exec mosquitto mosquitto_pub \
  -t 'parking/nice_sophia.A/status' \
  -m '{"parking_id":"nice_sophia.A","slot_id":"A-12","occupied":true}'

# → Le service controle-reservation envoie une notification FCM
```

4. **Confirmer la présence**

```
POST /confirm-reservation
{
  "spot_id": "A-12"
}
# → Change le statut de RESERVED à OCCUPIED
```

5. **Ou annuler si ce n'est pas le bon utilisateur**

```
POST /cancel-reservation
{
  "spot_id": "A-12"
}
# → Remet le statut à FREE
```

## Configuration avancée

### Modifier la base URL

Si l'API tourne sur un autre port ou serveur:

1. Aller dans "Environments" → "OptiPark Local"
2. Modifier la valeur de `base_url`
3. Exemples:
   - Production: `https://api.optipark.com`
   - Docker externe: `http://192.168.1.100:8000`
   - Port différent: `http://localhost:3000`

### Créer un nouvel environnement

Pour tester sur différents environnements (dev, staging, prod):

1. Dupliquer l'environnement "OptiPark Local"
2. Renommer (ex: "OptiPark Production")
3. Modifier `base_url` vers le serveur correspondant

## Dépannage

### Erreur: "Could not get response"

L'API n'est pas accessible.

**Solutions:**
```bash
# Vérifier que l'API tourne
docker-compose ps reservation

# Vérifier les logs
docker-compose logs reservation

# Redémarrer l'API
docker-compose restart reservation

# Vérifier la connexion
curl http://localhost:8000/health
```

### Erreur 400: "block_id missing"

Le body de la requête est mal formaté ou vide.

**Solution:** Vérifier que le Content-Type est `application/json` et que le body contient un JSON valide.

### Erreur: "NO_SPOT_AVAILABLE"

Toutes les places du parking sont occupées ou réservées.

**Solution:**
```bash
# Libérer quelques places via Redis
docker-compose exec redis redis-cli HSET spot:A-1 status 0
docker-compose exec redis redis-cli HSET spot:A-2 status 0

# Ou réinitialiser tout Redis
docker-compose up -d redis-init
```

### Variable {{reserved_spot_id}} non définie

La variable n'est remplie qu'après une réservation réussie.

**Solution:**
1. D'abord exécuter une requête "Reserve Spot"
2. Ensuite utiliser "Confirm" ou "Cancel"

Ou modifier manuellement:
1. Aller dans "Environments" → "OptiPark Local"
2. Remplir `reserved_spot_id` avec un ID valide (ex: "A-1")

## Export des résultats

Pour partager vos tests ou générer un rapport:

1. Exécuter un dossier de tests (Run folder)
2. Cliquer sur "Export Results"
3. Choisir le format (JSON, HTML, etc.)

## CLI avec Newman

Pour automatiser les tests en ligne de commande:

```bash
# Installer Newman
npm install -g newman

# Exécuter la collection
newman run OptiPark_API.postman_collection.json \
  -e OptiPark_Local.postman_environment.json

# Avec rapport HTML
newman run OptiPark_API.postman_collection.json \
  -e OptiPark_Local.postman_environment.json \
  --reporters cli,html \
  --reporter-html-export report.html
```

## Licence

Projet OptiPark - Polytech Nice Sophia SI5
