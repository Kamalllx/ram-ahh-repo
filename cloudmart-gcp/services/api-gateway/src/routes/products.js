'use strict';

const express = require('express');
const axios   = require('axios');
const { logger } = require('../lib/logger');

const router = express.Router();
const PRODUCT_SVC = process.env.PRODUCT_SERVICE_URL;

function fwd(req) {
  return {
    headers: {
      'Content-Type': 'application/json',
      'X-Request-ID': req.headers['x-request-id'] || require('uuid').v4(),
      'X-Forwarded-For': req.ip,
    },
    timeout: 10000,
  };
}

// GET /api/v1/products — list with pagination + filters
router.get('/', async (req, res, next) => {
  try {
    const { data } = await axios.get(`${PRODUCT_SVC}/products`, {
      ...fwd(req),
      params: req.query,
    });
    res.json(data);
  } catch (err) {
    next(proxyError(err));
  }
});

// GET /api/v1/products/search
router.get('/search', async (req, res, next) => {
  try {
    const { data } = await axios.get(`${PRODUCT_SVC}/products/search`, {
      ...fwd(req),
      params: req.query,
    });
    res.json(data);
  } catch (err) {
    next(proxyError(err));
  }
});

// GET /api/v1/products/:id
router.get('/:id', async (req, res, next) => {
  try {
    const { data } = await axios.get(`${PRODUCT_SVC}/products/${req.params.id}`, fwd(req));
    res.json(data);
  } catch (err) {
    next(proxyError(err));
  }
});

// POST /api/v1/products — admin only
router.post('/', async (req, res, next) => {
  try {
    const { data } = await axios.post(`${PRODUCT_SVC}/products`, req.body, fwd(req));
    res.status(201).json(data);
  } catch (err) {
    next(proxyError(err));
  }
});

// PUT /api/v1/products/:id
router.put('/:id', async (req, res, next) => {
  try {
    const { data } = await axios.put(`${PRODUCT_SVC}/products/${req.params.id}`, req.body, fwd(req));
    res.json(data);
  } catch (err) {
    next(proxyError(err));
  }
});

// DELETE /api/v1/products/:id
router.delete('/:id', async (req, res, next) => {
  try {
    await axios.delete(`${PRODUCT_SVC}/products/${req.params.id}`, fwd(req));
    res.status(204).send();
  } catch (err) {
    next(proxyError(err));
  }
});

function proxyError(err) {
  if (err.response) {
    const e = new Error(err.response.data?.detail || err.response.data?.error || 'Upstream error');
    e.status = err.response.status;
    return e;
  }
  logger.error({ msg: 'Product service unreachable', err: err.message });
  const e = new Error('Product service unavailable');
  e.status = 503;
  return e;
}

module.exports = router;
