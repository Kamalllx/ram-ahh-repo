'use strict';

const express  = require('express');
const helmet   = require('helmet');
const cors     = require('cors');
const { pool } = require('./db/postgres');
const { redis } = require('./cache/redis');
const usersRouter = require('./routes/users');

const app  = express();
const PORT = process.env.PORT || 8080;

app.use(helmet());
app.use(cors());
app.use(express.json());

app.get('/health', async (req, res) => {
  const checks = {};

  try {
    await pool.query('SELECT 1');
    checks.postgres = 'ok';
  } catch {
    checks.postgres = 'degraded';
  }

  try {
    await redis.ping();
    checks.redis = 'ok';
  } catch {
    checks.redis = 'degraded';
  }

  const healthy = Object.values(checks).every(v => v === 'ok');
  res.status(healthy ? 200 : 207).json({
    status: healthy ? 'ok' : 'degraded',
    service: 'user-service',
    checks,
  });
});

app.use('/users', usersRouter);

app.use((err, req, res, _next) => {
  console.error(JSON.stringify({ error: err.message, path: req.path }));
  res.status(err.status || 500).json({ error: err.message || 'Internal error' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(JSON.stringify({ severity: 'INFO', message: `User Service listening on :${PORT}` }));
});

module.exports = app;
