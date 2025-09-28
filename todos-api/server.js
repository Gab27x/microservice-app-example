'use strict';
const express = require('express')
const bodyParser = require("body-parser")
const jwt = require('express-jwt')

const ZIPKIN_URL = process.env.ZIPKIN_URL || 'http://127.0.0.1:9411/api/v2/spans';
const {Tracer, 
  BatchRecorder,
  jsonEncoder: {JSON_V2}} = require('zipkin');
  const CLSContext = require('zipkin-context-cls');  
const {HttpLogger} = require('zipkin-transport-http');
const zipkinMiddleware = require('zipkin-instrumentation-express').expressMiddleware;

const logChannel = process.env.REDIS_CHANNEL || 'log_channel';
const redisClient = require("redis").createClient({
  host: process.env.REDIS_HOST || 'localhost',
  port: process.env.REDIS_PORT || 6379,
  retry_strategy: function (options) {
      if (options.error && options.error.code === 'ECONNREFUSED') {
          return new Error('The server refused the connection');
      }
      if (options.total_retry_time > 1000 * 60 * 60) {
          return new Error('Retry time exhausted');
      }
      if (options.attempt > 10) {
          console.log('reattemtping to connect to redis, attempt #' + options.attempt)
          return undefined;
      }
      return Math.min(options.attempt * 100, 2000);
  }        
});
const port = process.env.TODO_API_PORT || 8082
const jwtSecret = process.env.JWT_SECRET || "myfancysecret"

const app = express()

// tracing
const ctxImpl = new CLSContext('zipkin');
const recorder = new  BatchRecorder({
  logger: new HttpLogger({
    endpoint: ZIPKIN_URL,
    jsonEncoder: JSON_V2
  })
});
const localServiceName = 'todos-api';
const tracer = new Tracer({ctxImpl, recorder, localServiceName});

// Body parser middleware (necesario para todos los endpoints)
app.use(bodyParser.urlencoded({ extended: false }))
app.use(bodyParser.json())

// Health check endpoint (sin autenticación, rate limiting ni JWT)
app.get('/health', function(req, res) {
  res.status(200).json({
    status: 'OK',
    service: 'todos-api',
    timestamp: new Date().toISOString()
  });
});

app.use(jwt({ secret: jwtSecret, algorithms: ['HS256'] }).unless({path: ['/health']}))
app.use(zipkinMiddleware({tracer}));
// Rate limiting distribuido con Redis (por IP o usuario JWT)
const { RateLimiterRedis } = require('rate-limiter-flexible');
const rlPoints = parseInt(process.env.RATE_LIMIT_POINTS || '100', 10);
const rlDuration = parseInt(process.env.RATE_LIMIT_DURATION || '60', 10);
const rlBlock = parseInt(process.env.RATE_LIMIT_BLOCK || '60', 10);
const rateLimiter = new RateLimiterRedis({
  storeClient: redisClient,
  keyPrefix: 'rlflx',
  points: rlPoints,
  duration: rlDuration,
  blockDuration: rlBlock
});
function rateLimitKey(req) {
  if (req.user && req.user.sub) return 'user:' + req.user.sub;
  return 'ip:' + (req.ip || req.connection.remoteAddress || 'unknown');
}
app.use(async function (req, res, next) {
  try {
    await rateLimiter.consume(rateLimitKey(req), 1);
    next();
  } catch (rejRes) {
    res.status(429).json({ message: 'Too Many Requests' });
  }
});
app.use(function (err, req, res, next) {
  if (err.name === 'UnauthorizedError') {
    res.status(401).send({ message: 'invalid token' })
  }
})

const routes = require('./routes')
routes(app, {tracer, redisClient, logChannel})

app.listen(port, function () {
  console.log('todo list RESTful API server started on: ' + port)
})
