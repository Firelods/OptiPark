const { Kafka } = require('kafkajs');
const Redis = require('ioredis');

// ----- Config via environment variables -----
const KAFKA_BROKERS = process.env.KAFKA_BROKERS || 'kafka:9092';
const KAFKA_GROUP_ID = process.env.KAFKA_GROUP_ID || 'parking-redis-writer';
const REDIS_HOST = process.env.REDIS_HOST || 'redis';
const REDIS_PORT = parseInt(process.env.REDIS_PORT || '6379', 10);

// IMPORTANT: Choose the Kafka topics you want to consume.
// If you keep your old 3 topics, leave as-is.
// If you later switch to one unified topic (recommended), set to ['parking.events'].
const topics = [
  'parking.nice_sophia.A',
  'parking.nice_sophia.B',
  'parking.nice_sophia.C',
];

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
  await consumer.connect();
  console.log('Kafka consumer connected.');

  await consumer.subscribe({ topics, fromBeginning: false });
  console.log('Kafka consumer subscribed to topics:', topics);

  await consumer.run({
    autoCommit: true,
    eachMessage: async ({ topic, message }) => {
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
          console.error('Failed to parse JSON value:', valueStr);
          return;
        }

        const { parking_id, slot_id, occupied, battery_mv, sent_at, received_at } = event;

        // Validate required schema fields
        if (!parking_id || !slot_id || typeof occupied !== 'boolean') {
          console.warn('Invalid MagneticRawEvent, missing required fields:', event);
          return;
        }

        // Keep your redis key format: parking:<A|B|C>:free and spot:<slot>
        const shortParkingId = parking_id.includes('.') ? parking_id.split('.').pop() : parking_id;

        const parkingFreeKey = `parking:${shortParkingId}:free`;
        const spotKey = `spot:${slot_id}`;

        // status: 1 occupied, 0 free (matches your init)
        const status = occupied ? 1 : 0;

        // Maintain free set correctly:
        // - occupied => remove from free set
        // - free     => add to free set
        if (occupied) {
          await redis.srem(parkingFreeKey, slot_id);
        } else {
          await redis.sadd(parkingFreeKey, slot_id);
        }

        // Update spot hash (preserve other fields: type, covered, etc.)
        const hashFields = {
          parking_id: shortParkingId,
          status: status.toString(),
        };

        if (typeof battery_mv === 'number') hashFields.battery_mv = battery_mv.toString();
        if (sent_at) hashFields.sent_at = sent_at;
        if (received_at) hashFields.received_at = received_at;

        await redis.hset(spotKey, hashFields);

        console.log(
          `Redis updated: topic=${topic} parking_id=${parking_id} short=${shortParkingId} slot_id=${slot_id} status=${status}`
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

// Clean shutdown for Docker
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
