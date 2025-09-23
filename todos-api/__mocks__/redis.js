// Simple in-memory mock for redis v2.8 client used in todos-api

class MockRedisClient {
  constructor() {
    this.store = new Map();
    this.pubsub = [];
  }
  get(key, cb) {
    if (cb) cb(null, this.store.get(key) || null);
  }
  setex(key, ttl, val, cb) {
    this.store.set(key, val);
    if (cb) cb(null, 'OK');
  }
  del(key, cb) {
    this.store.delete(key);
    if (cb) cb(null, 1);
  }
  publish(channel, message) {
    this.pubsub.push({ channel, message });
  }
}

module.exports.createClient = () => new MockRedisClient();


