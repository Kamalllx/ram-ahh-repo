'use strict';

// Start Cloud Trace first for distributed tracing
require('@google-cloud/trace-agent').start();

const express    = require('express');
const helmet     = require('helmet');
const cors       = require('cors');
const morgan     = require('morgan');
const compression = require('compression');
const rateLimit  = require('express-rate-limit');

const productsRouter = require('./routes/products');
const ordersRouter   = require('./routes/orders');
const usersRouter    = require('./routes/users');
const uploadRouter   = require('./routes/upload');
const authMiddleware = require('./middleware/auth');
const { logger }     = require('./lib/logger');
const { healthCheck }= require('./lib/health');

const app  = express();
const PORT = process.env.PORT || 8080;

// ── Security middleware ───────────────────────────────────────
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      imgSrc: ["'self'", 'storage.googleapis.com', 'data:'],
    },
  },
}));

app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || '*',
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// ── Rate limiting ─────────────────────────────────────────────
const limiter = rateLimit({
  windowMs: 60 * 1000,   // 1 minute
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' },
});
app.use('/api/', limiter);

// ── General middleware ────────────────────────────────────────
app.use(compression());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Structured logging for Cloud Logging
app.use(morgan('combined', {
  stream: {
    write: (message) => logger.info(message.trim()),
  },
}));

// ── Health endpoints (no auth) ────────────────────────────────
app.get('/health', healthCheck);
app.get('/ready', healthCheck);

// ── API routes ────────────────────────────────────────────────
app.use('/api/v1/users',    usersRouter);                          // public: register, login
app.use('/api/v1/products', productsRouter);                       // public: browse catalog
app.use('/api/v1/orders',   authMiddleware, ordersRouter);         // protected
app.use('/api/v1/upload',   authMiddleware, uploadRouter);         // protected

// ── 404 handler ───────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({ error: 'Not found', path: req.path });
});

// ── Error handler ─────────────────────────────────────────────
app.use((err, req, res, _next) => {
  logger.error({ err, path: req.path, method: req.method });

  if (err.name === 'UnauthorizedError') {
    return res.status(401).json({ error: 'Invalid or missing token' });
  }

  const status = err.status || err.statusCode || 500;
  const message = status < 500 ? err.message : 'Internal server error';
  res.status(status).json({ error: message });
});

// ── Start server ─────────────────────────────────────────────
app.listen(PORT, '0.0.0.0', () => {
  logger.info(`CloudMart API Gateway listening on :${PORT}`);
  logger.info(`Environment: ${process.env.NODE_ENV}`);
  logger.info(`Product Service: ${process.env.PRODUCT_SERVICE_URL}`);
  logger.info(`Order Service:   ${process.env.ORDER_SERVICE_URL}`);
  logger.info(`User Service:    ${process.env.USER_SERVICE_URL}`);
});

module.exports = app; // for testing
