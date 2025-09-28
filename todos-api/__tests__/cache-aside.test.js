'use strict';

// Mock redis module used by server.js
jest.mock('redis');

const request = require('http');
const express = require('express');
const bodyParser = require('body-parser');
const jwt = require('express-jwt');

// Reuse the controller to avoid forking server port management
const TodoController = require('../todoController');

function buildApp(mockRedis) {
  const app = express();
  app.use(bodyParser.urlencoded({ extended: false }));
  app.use(bodyParser.json());
  // Stub JWT to avoid auth during tests
  app.use((req, res, next) => { req.user = { username: 'admin' }; next(); });

  const controller = new TodoController({ tracer: { scoped: (fn) => fn(), id: {} }, redisClient: mockRedis, logChannel: 'log_channel' });
  app.get('/todos', (req, res) => controller.list(req, res));
  app.post('/todos', (req, res) => controller.create(req, res));
  app.delete('/todos/:taskId', (req, res) => controller.delete(req, res));
  return app;
}

describe('Cache-aside in todos-api', () => {
  test('GET /todos returns MISS first then HIT from Redis', async () => {
    const redis = require('redis').createClient();
    const app = buildApp(redis);
    const server = app.listen(0);
    const base = `http://127.0.0.1:${server.address().port}`;

    // First call -> MISS (controller populates redis)
    let code1, cacheHdr1;
    await new Promise((resolve) => {
      const req = request.get(`${base}/todos`, (res) => {
        code1 = res.statusCode;
        cacheHdr1 = res.headers['x-cache'] || '';
        res.resume();
        res.on('end', resolve);
      });
      req.on('error', resolve);
    });

    // Second call -> HIT
    let code2, cacheHdr2;
    await new Promise((resolve) => {
      const req = request.get(`${base}/todos`, (res) => {
        code2 = res.statusCode;
        cacheHdr2 = res.headers['x-cache'] || '';
        res.resume();
        res.on('end', resolve);
      });
      req.on('error', resolve);
    });

    server.close();

    expect(code1).toBe(200);
    expect(cacheHdr1).toBe('MISS');
    expect(code2).toBe(200);
    expect(cacheHdr2).toBe('HIT');
  });

  test('POST /todos invalidates cache; next GET becomes MISS again', async () => {
    const redis = require('redis').createClient();
    const app = buildApp(redis);
    const server = app.listen(0);
    const base = `http://127.0.0.1:${server.address().port}`;

    // Prime cache with a GET -> HIT later
    await new Promise((resolve) => {
      const req = request.get(`${base}/todos`, (res) => { res.resume(); res.on('end', resolve); });
      req.on('error', resolve);
    });

    // POST create todo -> invalidates cache
    await new Promise((resolve) => {
      const req = request.request(`${base}/todos`, { method: 'POST', headers: { 'Content-Type': 'application/json' } }, (res) => { res.resume(); res.on('end', resolve); });
      req.write(JSON.stringify({ content: 'new item' }));
      req.end();
      req.on('error', resolve);
    });

    // Next GET -> MISS expected
    let cacheHdr;
    await new Promise((resolve) => {
      const req = request.get(`${base}/todos`, (res) => { cacheHdr = res.headers['x-cache'] || ''; res.resume(); res.on('end', resolve); });
      req.on('error', resolve);
    });

    server.close();
    expect(cacheHdr).toBe('MISS');
  });
});


