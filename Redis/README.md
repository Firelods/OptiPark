# Initialisation Redis - OptiPark

## ⚠️ Problème résolu

Le fichier `init_parking.redis` contient des commentaires (`#`) qui ne sont **PAS** compatibles avec `redis-cli` en mode batch.

**❌ Ne PAS utiliser :**
```bash
docker exec -i redis redis-cli < init_parking.redis  # ERREUR!
```

## ✅ Solution automatique (Recommandée)

### Avec Docker Compose

Le service `redis-init` s'exécute automatiquement au démarrage :

```bash
# Lancer tous les services (y compris l'initialisation Redis)
docker-compose up -d

# Vérifier les logs de l'initialisation
docker logs redis-init

# Vérifier que les données sont chargées
docker exec redis redis-cli DBSIZE
```

**Note:** Le service `redis-init` s'arrête automatiquement après avoir chargé les données.

## 📋 Solution manuelle

### Option 1: Script shell (Linux/Mac/Git Bash)

```bash
cd Redis

# Rendre le script exécutable
chmod +x load_parking_data.sh

# Exécuter le script
./load_parking_data.sh
```

### Option 2: Commande directe (Linux/Mac/Git Bash)

```bash
# Depuis le dossier Redis/
sed 's/#.*//' init_parking.redis | sed ':a;/\\$/{N;s/\\\n/ /;ta}' | grep -v '^[[:space:]]*$' | docker exec -i redis redis-cli
```

### Option 3: PowerShell (Windows)

```powershell
# Depuis le dossier Redis/
# Cette commande est complexe à cause des lignes de continuation (\)
# Il est recommandé d'utiliser Git Bash ou WSL pour Windows
# Ou d'utiliser le docker-compose (Option 1)

# Si vous devez absolument utiliser PowerShell:
$content = Get-Content init_parking.redis -Raw
$content = $content -replace '#.*', ''
$content = $content -replace '\\\r?\n\s*', ' '
$content -split "`n" | Where-Object { $_.Trim() -ne '' } | docker exec -i redis redis-cli
```

## 🔍 Vérification

### Vérifier le nombre de clés

```bash
docker exec redis redis-cli DBSIZE
```

Vous devriez voir environ 60 clés (20 places par parking × 3 parkings).

### Vérifier les places du parking A

```bash
docker exec redis redis-cli KEYS "spot:A-*"
```

### Afficher les détails d'une place

```bash
docker exec redis redis-cli HGETALL spot:A-1
```

Résultat attendu :
```
1) "status"
2) "FREE"
3) "type"
4) "COVERED"
5) "parking_id"
6) "A"
```

## 🌐 Interface Redis Insight

Visualiser les données via l'interface web :

1. Ouvrir http://localhost:8001
2. Se connecter à Redis (si ce n'est pas déjà fait)
3. Explorer les clés dans l'onglet "Browser"

## 📊 Structure des données

### Parkings disponibles

- **Parking A**: 20 spots
  - Row 0 (covered): 5 spots (3 COVERED, 2 PMR)
  - Row 1: 5 spots (3 NORMAL, 2 PMR)
  - Row 2: 5 spots (5 NORMAL)
  - Row 3 (EV): 5 spots (5 EV)

- **Parking B**: 20 spots (même structure)
- **Parking C**: 20 spots (même structure)

### Format des clés

`spot:{PARKING_ID}-{NUMERO}`

Exemples :
- `spot:A-1` : Place 1 du parking A
- `spot:B-15` : Place 15 du parking B
- `spot:C-20` : Place 20 du parking C

### Champs d'une place

- `status` : FREE, OCCUPIED, ou RESERVED
- `type` : NORMAL, COVERED, PMR, ou EV
- `parking_id` : A, B, ou C

## 🔄 Réinitialiser Redis

```bash
# Méthode 1: Relancer le service redis-init
docker-compose up -d redis-init

# Méthode 2: Vider Redis et recharger manuellement
docker exec redis redis-cli FLUSHALL
cd Redis && ./load_parking_data.sh
```

## 📁 Fichiers

- `init_parking.redis` : Script Redis avec commentaires (fichier source)
- `init_redis.sh` : Script d'initialisation pour Docker (utilisé par redis-init)
- `load_parking_data.sh` : Script manuel pour charger les données
- `README.md` : Ce fichier

## 🐛 Dépannage

### Erreur: "unknown command '#'"

C'est normal ! Vous avez essayé d'exécuter le script directement sans filtrer les commentaires.
Utilisez l'une des solutions ci-dessus.

### Aucune clé dans Redis

1. Vérifier que Redis est bien démarré :
   ```bash
   docker ps | grep redis
   ```

2. Vérifier les logs de redis-init :
   ```bash
   docker logs redis-init
   ```

3. Relancer l'initialisation :
   ```bash
   docker-compose up -d redis-init
   ```
