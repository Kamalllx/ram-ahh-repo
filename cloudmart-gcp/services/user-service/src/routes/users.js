'use strict';

const express  = require('express');
const bcrypt   = require('bcryptjs');
const jwt      = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const { pool } = require('../db/postgres');
const { setSession, getSession, invalidateSession } = require('../cache/redis');

const router     = express.Router();
const JWT_SECRET = process.env.JWT_SECRET;
const JWT_ISSUER = 'cloudmart';

function makeToken(user) {
  return jwt.sign(
    { sub: user.id, email: user.email, role: user.role },
    JWT_SECRET,
    { expiresIn: '7d', issuer: JWT_ISSUER, algorithm: 'HS256' },
  );
}

// POST /users/register
router.post('/register', async (req, res, next) => {
  const { email, password, full_name, phone } = req.body;

  if (!email || !password || !full_name) {
    return res.status(400).json({ error: 'email, password, and full_name are required' });
  }
  if (password.length < 8) {
    return res.status(400).json({ error: 'Password must be at least 8 characters' });
  }

  try {
    const existing = await pool.query('SELECT id FROM users WHERE email = $1', [email.toLowerCase()]);
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'Email already registered' });
    }

    const hash = await bcrypt.hash(password, 12);
    const { rows } = await pool.query(
      `INSERT INTO users (email, password_hash, full_name, phone)
       VALUES ($1, $2, $3, $4)
       RETURNING id, email, full_name, role, created_at`,
      [email.toLowerCase(), hash, full_name, phone || null],
    );

    const user  = rows[0];
    const token = makeToken(user);
    await setSession(user.id, token, { email: user.email });

    res.status(201).json({ user, token });
  } catch (err) {
    next(err);
  }
});

// POST /users/login
router.post('/login', async (req, res, next) => {
  const { email, password } = req.body;
  if (!email || !password) {
    return res.status(400).json({ error: 'email and password required' });
  }

  try {
    const { rows } = await pool.query(
      'SELECT id, email, full_name, role, password_hash, is_active FROM users WHERE email = $1',
      [email.toLowerCase()],
    );

    const user = rows[0];
    if (!user || !user.is_active) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const match = await bcrypt.compare(password, user.password_hash);
    if (!match) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const token = makeToken(user);
    await setSession(user.id, token, { email: user.email, role: user.role });

    const { password_hash, ...safeUser } = user;
    res.json({ user: safeUser, token });
  } catch (err) {
    next(err);
  }
});

// POST /users/refresh
router.post('/refresh', async (req, res, next) => {
  const { token } = req.body;
  if (!token) return res.status(400).json({ error: 'token required' });

  try {
    const payload = jwt.verify(token, JWT_SECRET, { issuer: JWT_ISSUER, ignoreExpiration: true });
    const session = await getSession(payload.sub, token);
    if (!session) {
      return res.status(401).json({ error: 'Session not found or expired' });
    }

    const { rows } = await pool.query(
      'SELECT id, email, full_name, role, is_active FROM users WHERE id = $1',
      [payload.sub],
    );
    const user = rows[0];
    if (!user || !user.is_active) {
      return res.status(401).json({ error: 'Account not found or disabled' });
    }

    await invalidateSession(payload.sub, token);
    const newToken = makeToken(user);
    await setSession(user.id, newToken, { email: user.email });

    res.json({ user, token: newToken });
  } catch (err) {
    next(err);
  }
});

// GET /users/:id
router.get('/:id', async (req, res, next) => {
  try {
    const { rows } = await pool.query(
      'SELECT id, email, full_name, role, phone, address, created_at FROM users WHERE id = $1 AND is_active = true',
      [req.params.id],
    );
    if (!rows[0]) return res.status(404).json({ error: 'User not found' });
    res.json(rows[0]);
  } catch (err) {
    next(err);
  }
});

// PUT /users/:id
router.put('/:id', async (req, res, next) => {
  const { full_name, phone, address } = req.body;

  try {
    const { rows } = await pool.query(
      `UPDATE users
       SET full_name   = COALESCE($1, full_name),
           phone       = COALESCE($2, phone),
           address     = COALESCE($3::jsonb, address),
           updated_at  = NOW()
       WHERE id = $4 AND is_active = true
       RETURNING id, email, full_name, role, phone, address, updated_at`,
      [full_name || null, phone || null, address ? JSON.stringify(address) : null, req.params.id],
    );
    if (!rows[0]) return res.status(404).json({ error: 'User not found' });
    res.json(rows[0]);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
