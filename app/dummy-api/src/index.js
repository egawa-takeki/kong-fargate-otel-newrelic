import express from 'express';
import { trace, context, propagation } from '@opentelemetry/api';

const app = express();
const PORT = process.env.PORT || 3000;

// Downstream API URL (Service Discovery or environment variable)
const DOWNSTREAM_API_URL = process.env.DOWNSTREAM_API_URL || 'http://downstream-api.kong-otel-dev.local:3001';

// Middleware to parse JSON
app.use(express.json());

// Request logging middleware
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);

  // Log all tracing-related headers for debugging
  console.log('=== TRACING HEADERS ===');
  console.log(`  traceparent: ${req.headers.traceparent || 'NOT SET'}`);
  console.log(`  tracestate: ${req.headers.tracestate || 'NOT SET'}`);
  console.log(`  x-amzn-trace-id: ${req.headers['x-amzn-trace-id'] || 'NOT SET'}`);
  console.log(`  x-request-id: ${req.headers['x-request-id'] || 'NOT SET'}`);
  console.log(`  x-b3-traceid: ${req.headers['x-b3-traceid'] || 'NOT SET'}`);
  console.log('=== ALL HEADERS ===');
  console.log(JSON.stringify(req.headers, null, 2));
  console.log('=== END HEADERS ===');

  next();
});

// Dummy user data
const users = [
  { id: 1, name: 'Alice', email: 'alice@example.com' },
  { id: 2, name: 'Bob', email: 'bob@example.com' },
  { id: 3, name: 'Charlie', email: 'charlie@example.com' },
];

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Get all users
app.get('/api/users', (req, res) => {
  const tracer = trace.getTracer('dummy-api');

  tracer.startActiveSpan('fetch-users', (span) => {
    try {
      // Simulate some processing time
      const delay = Math.random() * 100;
      span.setAttribute('user.count', users.length);
      span.setAttribute('processing.delay_ms', delay);

      setTimeout(() => {
        span.end();
        res.json({
          data: users,
          total: users.length,
        });
      }, delay);
    } catch (error) {
      span.recordException(error);
      span.end();
      res.status(500).json({ error: 'Internal server error' });
    }
  });
});

// Get user by ID
app.get('/api/users/:id', (req, res) => {
  const tracer = trace.getTracer('dummy-api');

  tracer.startActiveSpan('fetch-user-by-id', (span) => {
    try {
      const userId = parseInt(req.params.id, 10);
      span.setAttribute('user.id', userId);

      const user = users.find(u => u.id === userId);

      if (user) {
        span.setAttribute('user.found', true);
        span.end();
        res.json({ data: user });
      } else {
        span.setAttribute('user.found', false);
        span.end();
        res.status(404).json({ error: 'User not found' });
      }
    } catch (error) {
      span.recordException(error);
      span.end();
      res.status(500).json({ error: 'Internal server error' });
    }
  });
});

// Create user (dummy - doesn't persist)
app.post('/api/users', (req, res) => {
  const tracer = trace.getTracer('dummy-api');

  tracer.startActiveSpan('create-user', (span) => {
    try {
      const { name, email } = req.body;

      if (!name || !email) {
        span.setAttribute('validation.failed', true);
        span.end();
        return res.status(400).json({ error: 'Name and email are required' });
      }

      const newUser = {
        id: users.length + 1,
        name,
        email,
      };

      span.setAttribute('user.id', newUser.id);
      span.setAttribute('user.name', newUser.name);

      // Add to in-memory array (for demo purposes)
      users.push(newUser);

      span.end();
      res.status(201).json({ data: newUser });
    } catch (error) {
      span.recordException(error);
      span.end();
      res.status(500).json({ error: 'Internal server error' });
    }
  });
});

// Chain endpoint - calls downstream-api to demonstrate distributed tracing
app.get('/api/chain', async (req, res) => {
  const tracer = trace.getTracer('dummy-api');

  tracer.startActiveSpan('chain-request', async (span) => {
    try {
      span.setAttribute('downstream.url', DOWNSTREAM_API_URL);

      console.log(`Calling downstream API: ${DOWNSTREAM_API_URL}/api/data`);

      // Propagate trace context to downstream service
      // The http instrumentation automatically adds traceparent header
      const downstreamResponse = await fetch(`${DOWNSTREAM_API_URL}/api/data`);

      if (!downstreamResponse.ok) {
        span.setAttribute('downstream.status', downstreamResponse.status);
        span.setAttribute('downstream.success', false);
        span.end();
        return res.status(downstreamResponse.status).json({
          error: 'Downstream API error',
          status: downstreamResponse.status,
        });
      }

      const downstreamData = await downstreamResponse.json();

      span.setAttribute('downstream.status', 200);
      span.setAttribute('downstream.success', true);

      // Combine with local data
      const result = {
        message: 'Chain request completed successfully',
        localData: {
          service: 'dummy-api',
          userCount: users.length,
          timestamp: new Date().toISOString(),
        },
        downstreamData: downstreamData,
      };

      span.end();
      res.json(result);
    } catch (error) {
      console.error('Chain request error:', error);
      span.recordException(error);
      span.setAttribute('downstream.error', error.message);
      span.end();
      res.status(500).json({
        error: 'Failed to call downstream service',
        details: error.message,
      });
    }
  });
});

// Chain endpoint with specific data ID
app.get('/api/chain/:id', async (req, res) => {
  const tracer = trace.getTracer('dummy-api');

  tracer.startActiveSpan('chain-request-by-id', async (span) => {
    try {
      const dataId = req.params.id;
      span.setAttribute('downstream.url', DOWNSTREAM_API_URL);
      span.setAttribute('data.requested_id', dataId);

      console.log(`Calling downstream API: ${DOWNSTREAM_API_URL}/api/data/${dataId}`);

      const downstreamResponse = await fetch(`${DOWNSTREAM_API_URL}/api/data/${dataId}`);
      const downstreamData = await downstreamResponse.json();

      span.setAttribute('downstream.status', downstreamResponse.status);
      span.setAttribute('downstream.success', downstreamResponse.ok);

      if (!downstreamResponse.ok) {
        span.end();
        return res.status(downstreamResponse.status).json({
          error: 'Downstream API error',
          status: downstreamResponse.status,
          downstreamError: downstreamData,
        });
      }

      const result = {
        message: 'Chain request completed successfully',
        requestedId: dataId,
        localData: {
          service: 'dummy-api',
          timestamp: new Date().toISOString(),
        },
        downstreamData: downstreamData,
      };

      span.end();
      res.json(result);
    } catch (error) {
      console.error('Chain request error:', error);
      span.recordException(error);
      span.setAttribute('downstream.error', error.message);
      span.end();
      res.status(500).json({
        error: 'Failed to call downstream service',
        details: error.message,
      });
    }
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Error handler
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(500).json({ error: 'Internal server error' });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Dummy API server running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
  console.log(`Users API: http://localhost:${PORT}/api/users`);
  console.log(`Chain API: http://localhost:${PORT}/api/chain`);
  console.log(`Downstream API URL: ${DOWNSTREAM_API_URL}`);
});
