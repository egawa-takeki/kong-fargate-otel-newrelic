import express from 'express';
import { trace } from '@opentelemetry/api';

const app = express();
const PORT = process.env.PORT || 3001;

// Middleware to parse JSON
app.use(express.json());

// Request logging middleware
app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.path}`);

  // Log traceparent header if present (for debugging)
  if (req.headers.traceparent) {
    console.log(`  traceparent: ${req.headers.traceparent}`);
  }

  next();
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    service: 'downstream-api',
    timestamp: new Date().toISOString()
  });
});

// Data endpoint - simulates a downstream data service
app.get('/api/data', (req, res) => {
  const tracer = trace.getTracer('downstream-api');

  tracer.startActiveSpan('fetch-downstream-data', (span) => {
    try {
      // Simulate database or external service call
      const processingTime = Math.random() * 200 + 50;
      span.setAttribute('processing.time_ms', processingTime);
      span.setAttribute('data.source', 'downstream-database');

      setTimeout(() => {
        const data = {
          id: Math.floor(Math.random() * 1000),
          message: 'Data from downstream service',
          timestamp: new Date().toISOString(),
          metadata: {
            source: 'downstream-api',
            version: '1.0.0',
            processingTimeMs: Math.round(processingTime),
          },
        };

        span.setAttribute('data.id', data.id);
        span.end();

        res.json({
          success: true,
          data
        });
      }, processingTime);
    } catch (error) {
      span.recordException(error);
      span.end();
      res.status(500).json({ error: 'Internal server error' });
    }
  });
});

// Complex data endpoint with multiple operations
app.get('/api/data/:id', (req, res) => {
  const tracer = trace.getTracer('downstream-api');

  tracer.startActiveSpan('fetch-data-by-id', (span) => {
    try {
      const dataId = req.params.id;
      span.setAttribute('data.requested_id', dataId);

      // Simulate lookup
      const found = Math.random() > 0.2; // 80% success rate

      setTimeout(() => {
        if (found) {
          const data = {
            id: dataId,
            name: `Resource-${dataId}`,
            description: `Detailed data for resource ${dataId}`,
            createdAt: new Date(Date.now() - Math.random() * 86400000 * 30).toISOString(),
            updatedAt: new Date().toISOString(),
          };

          span.setAttribute('data.found', true);
          span.end();
          res.json({ success: true, data });
        } else {
          span.setAttribute('data.found', false);
          span.end();
          res.status(404).json({ error: 'Data not found', id: dataId });
        }
      }, Math.random() * 100 + 30);
    } catch (error) {
      span.recordException(error);
      span.end();
      res.status(500).json({ error: 'Internal server error' });
    }
  });
});

// POST endpoint for data processing
app.post('/api/data', (req, res) => {
  const tracer = trace.getTracer('downstream-api');

  tracer.startActiveSpan('process-data', (span) => {
    try {
      const { payload } = req.body;

      span.setAttribute('payload.size', JSON.stringify(payload || {}).length);
      span.setAttribute('operation', 'data-processing');

      // Simulate processing
      setTimeout(() => {
        const result = {
          processed: true,
          resultId: `result-${Date.now()}`,
          inputSize: JSON.stringify(payload || {}).length,
          processedAt: new Date().toISOString(),
        };

        span.setAttribute('result.id', result.resultId);
        span.end();

        res.status(201).json({ success: true, result });
      }, Math.random() * 150 + 50);
    } catch (error) {
      span.recordException(error);
      span.end();
      res.status(500).json({ error: 'Internal server error' });
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
  console.log(`Downstream API server running on port ${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
  console.log(`Data API: http://localhost:${PORT}/api/data`);
});
