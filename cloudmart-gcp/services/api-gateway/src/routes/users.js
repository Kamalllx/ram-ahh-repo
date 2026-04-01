'use strict';

const express = require('express');
const axios   = require('axios');
const { logger } = require('../lib/logger');

const router = express.Router();
const USER_SVC = process.env.USER_SERVICE_URL;

function fwd(req) {
  return {
    headers: { 'Content-Type': 'application/json' },
    timeout: 10000,
  };
}

// POST /api/v1/users/register
router.post('/register', async (req, res, next) => {
  try {
    const { data } = await axios.post(`${USER_SVC}/users/register`, req.body, fwd(req));
    res.status(201).json(data);
  } catch (err) {
    next(proxyError(err));
  }
});

// POST /api/v1/users/login
router.post('/login', async (req, res, next) => {
  try {
    const { data } = await axios.post(`${USER_SVC}/users/login`, req.body, fwd(req));
    res.json(data);
  } catch (err) {
    next(proxyError(err));
  }
});

// POST /api/v1/users/refresh
router.post('/refresh', async (req, res, next) => {
  try {
    const { data } = await axios.post(`${USER_SVC}/users/refresh`, req.body, fwd(req));
    res.json(data);
  } catch (err) {
    next(proxyError(err));
  }
});

// GET /api/v1/users/profile — protected, user reads own profile
router.get('/profile', require('../middleware/auth'), async (req, res, next) => {
  try {
    const { data } = await axios.get(`${USER_SVC}/users/${req.user.sub}`, {
      ...fwd(req),
      headers: { ...fwd(req).headers, 'X-User-ID': req.user.sub },
    });
    res.json(data);
  } catch (err) {
    next(proxyError(err));
  }
});

// PUT /api/v1/users/profile
router.put('/profile', require('../middleware/auth'), async (req, res, next) => {
  try {
    const { data } = await axios.put(`${USER_SVC}/users/${req.user.sub}`, req.body, {
      ...fwd(req),
      headers: { ...fwd(req).headers, 'X-User-ID': req.user.sub },
    });
    res.json(data);
  } catch (err) {
    next(proxyError(err));
  }
});

function proxyError(err) {
  if (err.response) {
    const e = new Error(err.response.data?.error || 'User service error');
    e.status = err.response.status;
    return e;
  }
  logger.error({ msg: 'User service unreachable', err: err.message });
  const e = new Error('User service unavailable');
  e.status = 503;
  return e;
}

module.exports = router;
