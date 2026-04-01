'use strict';

const Redis = require('ioredis');

const redis = new Redis({
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379'),
  maxRetriesPerRequest: 3,
  retryStrategy: (times) => Math.min(times * 50, 2000),
  lazyConnect: true,
});

redis.on('error', (err) => {
  console.error(JSON.stringify({ severity: 'WARNING', message: 'Redis error', error: err.message }));
});

const SESSION_TTL = 60 * 60 * 24 * 7; // 7 days

async function setSession(userId, token, data) {
  const key = `session:${userId}:${token.slice(-8)}`;
  await redis.setex(key, SESSION_TTL, JSON.stringify(data));
}

async function getSession(userId, token) {
  const key = `session:${userId}:${token.slice(-8)}`;
  const raw = await redis.get(key);
  return raw ? JSON.parse(raw) : null;
}

async function invalidateSession(userId, token) {
  const key = `session:${userId}:${token.slice(-8)}`;
  await redis.del(key);
}

async function invalidateAllSessions(userId) {
  const keys = await redis.keys(`session:${userId}:*`);
  if (keys.length > 0) await redis.del(...keys);
}

module.exports = { redis, setSession, getSession, invalidateSession, invalidateAllSessions };
