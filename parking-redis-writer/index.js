const { Kafka } = require('kafkajs');
const Redis = require('ioredis');

// ----- Config via variables d'environnement -----
const KAFKA_BROKERS = process.env.KAFKA_BROKERS || 'kafka:9092';
const KAFKA_GROUP_ID = process.env.KAFKA_GROUP_ID || 'parking-redis-writer';
const REDIS_HOST = process.env.REDIS_HOST || 'redis';
const REDIS_PORT = parseInt(process.env.REDIS_PORT || '6379', 10);

const kafka = new Kafka({
  clientId: 'parking-redis-writer',
  brokers: KAFKA_BROKERS.split(','),
  retry: {
    initialRetryTime: 300,
    retries: 10,
    maxRetryTime: 30000,
    multiplier: 2,
  },
  connectionTimeout: 10000,
  requestTimeout: 30000,
});

const redis = new Redis({
  host: REDIS_HOST,
  port: REDIS_PORT,
  lazyConnect: true,
});

const topics = [
  'parking.nice_sophia.A',
  'parking.nice_sophia.B',
  'parking.nice_sophia.C',
];

async function run() {
  console.log('Connecting to Redis...');
  await redis.connect();
  console.log('Redis connected.');

  const consumer = kafka.consumer({
    groupId: KAFKA_GROUP_ID,
    retry: {
      initialRetryTime: 300,
      retries: 10,
      maxRetryTime: 30000,
    },
  });

  console.log('Connecting Kafka consumer...');
  let connected = false;
  let retryCount = 0;
  const maxRetries = 10;

  while (!connected && retryCount < maxRetries) {
    try {
      await consumer.connect();
      console.log('Kafka consumer connected.');

      await consumer.subscribe({ topics, fromBeginning: false });
      console.log('Kafka consumer subscribed to topics:', topics);
      connected = true;
    } catch (err) {
      retryCount++;
      const waitTime = Math.min(1000 * Math.pow(2, retryCount), 30000);
      console.error(`Failed to connect to Kafka (attempt ${retryCount}/${maxRetries}):`, err.message);
      console.log(`Retrying in ${waitTime}ms...`);
      await new Promise(resolve => setTimeout(resolve, waitTime));
    }
  }

  if (!connected) {
    throw new Error('Failed to connect to Kafka after maximum retries');
  }

  await consumer.run({
    autoCommit: true,
    eachMessage: async ({ topic, partition, message }) => {
      try {
        const valueStr = message.value?.toString();
        if (!valueStr) {
          console.warn('Received message without value, skipping');
          return;
        }

        let event;
        try {
          event = JSON.parse(valueStr);
        } catch (err) {
          console.error('Failed to parse JSON value:', valueStr, err);
          return;
        }

        const { parking_id, slot_id, occupied, battery_mv, sent_at, received_at } = event;

        if (!parking_id || !slot_id || typeof occupied !== 'boolean') {
          console.warn('Invalid MagneticRawEvent, missing required fields:', event);
          return;
        }
        if (occupied){
          console.log(`Place occupée parking_id=${parking_id} slot_id=${slot_id} pas de mise à jour Redis.`);
          return
        } 

        const status = occupied ? 1 : 0;

        // 1) Ajout de la place dans le set du parking
        const parkingSpotsKey = `parking:${parking_id}:spots`;
        await redis.sadd(parkingSpotsKey, slot_id);

        // 2) Mise à jour du hash de la place
        const spotKey = `spot:${slot_id}`;
        const hashFields = {
          parking_id: parking_id,
          status: status.toString(),
        };

        if (typeof battery_mv === 'number') {
          hashFields.battery_mv = battery_mv.toString();
        }
        if (sent_at) {
          hashFields.sent_at = sent_at;
        }
        if (received_at) {
          hashFields.received_at = received_at;
        }

        await redis.hset(spotKey, hashFields);

        console.log(
          `Updated Redis for event topic=${topic} parking_id=${parking_id} slot_id=${slot_id} status=${status}`
        );
      } catch (err) {
        console.error('Error processing message from Kafka:', err);
      }
    },
  });
}

run().catch((err) => {
  console.error('Fatal error in parking-redis-writer:', err);
  process.exit(1);
});

// Gestion propre des signaux pour Docker
process.on('SIGINT', async () => {
  console.log('Received SIGINT, closing Redis...');
  await redis.quit();
  process.exit(0);
});

process.on('SIGTERM', async () => {
  console.log('Received SIGTERM, closing Redis...');
  await redis.quit();
  process.exit(0);
});
