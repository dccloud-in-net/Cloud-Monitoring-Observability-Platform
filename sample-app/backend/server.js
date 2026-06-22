// Backend service — Node.js / Express.
// Auto-instrumented by the OpenTelemetry Operator (Instrumentation CR).
const express = require('express');
const app = express();

const ITEMS = [
  'cap', 'shirt', 'mug', 'sticker', 'notebook', 'hoodie', 'pin', 'water-bottle'
];

app.get('/healthz', (_req, res) => res.send('ok'));

app.get('/inventory', (_req, res) => {
  // Simulate downstream latency
  const ms = 10 + Math.random() * 150;
  setTimeout(() => {
    if (Math.random() < 0.02) {
      return res.status(500).json({ error: 'synthetic backend failure' });
    }
    res.json({ items: ITEMS, generated_at: new Date().toISOString() });
  }, ms);
});

const port = process.env.PORT || 8080;
app.listen(port, () => {
  console.log(JSON.stringify({ level: 'info', msg: 'backend listening', port }));
});
