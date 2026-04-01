'use strict';

const express = require('express');
const axios   = require('axios');
const { logger } = require('../lib/logger');

const router = express.Router();
const ORDER_SVC = process.env.ORDER_SERVICE_URL;

function fwd(req) {
  return {
    headers: {
      'Content-Type': 'application/json',
      'X-User-ID':    req.user.sub,
      'X-User-Email': req.user.email,
      'X-Request-ID': req.headers['x-request-id'] || require('uuid').v4(),
    },
    timeout: 15000,
  };
}

// GET /api/v1/orders — list user's orders
router.get('/', async (req, res, next) => {
  try {
    const { data } = await axios.get(`${ORDER_SVC}/orders`, {
      ...fwd(req),
      params: { user_id: req.user.sub, ...req.query },
    });
    res.json(data);
  } catch (err) {
    next(proxyError(err));
  }
});

// GET /api/v1/orders/:id
router.get('/:id', async (req, res, next) => {
  try {
    const { data } = await axios.get(`${ORDER_SVC}/orders/${req.params.id}`, fwd(req));

    // Only let users see their own orders (unless admin)
    if (data.user_id !== req.user.sub && req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Forbidden' });
    }

    res.json(data);
  } catch (err) {
    next(proxyError(err));
  }
});

// POST /api/v1/orders — place a new order
router.post('/', async (req, res, next) => {
  try {
    const payload = { ...req.body, user_id: req.user.sub };
    const { data } = await axios.post(`${ORDER_SVC}/orders`, payload, fwd(req));
    res.status(201).json(data);
  } catch (err) {
    next(proxyError(err));
  }
});

// PATCH /api/v1/orders/:id/cancel
router.patch('/:id/cancel', async (req, res, next) => {
  try {
    const { data } = await axios.patch(
      `${ORDER_SVC}/orders/${req.params.id}/cancel`,
      { user_id: req.user.sub },
      fwd(req),
    );
    res.json(data);
  } catch (err) {
    next(proxyError(err));
  }
});

// PATCH /api/v1/orders/:id/status — admin only
router.patch('/:id/status', async (req, res, next) => {
  if (req.user.role !== 'admin') {
    return res.status(403).json({ error: 'Forbidden' });
  }
  try {
    const { data } = await axios.patch(
      `${ORDER_SVC}/orders/${req.params.id}/status`,
      req.body,
      fwd(req),
    );
    res.json(data);
  } catch (err) {
    next(proxyError(err));
  }
});

function proxyError(err) {
  if (err.response) {
    const e = new Error(err.response.data?.detail || 'Order service error');
    e.status = err.response.status;
    return e;
  }
  logger.error({ msg: 'Order service unreachable', err: err.message });
  const e = new Error('Order service unavailable');
  e.status = 503;
  return e;
}

module.exports = router;
