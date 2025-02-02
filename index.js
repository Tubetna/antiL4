const express = require('express');
const rateLimit = require('express-rate-limit');
const ip = require('ip');
const helmet = require('helmet');
const slowDown = require('express-slow-down');
const winston = require('winston');
const bodyParser = require('body-parser');

const app = express();
const PORT = 3000;

// Cấu hình logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.json(),
  transports: [
    new winston.transports.File({ filename: 'error.log', level: 'error' }),
    new winston.transports.File({ filename: 'combined.log' })
  ]
});

// Sử dụng Helmet để bảo vệ headers
app.use(helmet());

// Giới hạn kích thước body request
app.use(bodyParser.json({ limit: '10kb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '10kb' }));

// Danh sách IP bị chặn (blacklist)
const blacklist = ['192.168.1.100', '10.0.0.1'];
const suspiciousIPs = new Map(); // Lưu trữ các IP đáng ngờ

// Middleware để chặn IP trong blacklist và monitor suspicious behavior
app.use((req, res, next) => {
  const clientIP = req.ip || req.connection.remoteAddress;
  
  // Kiểm tra blacklist
  if (blacklist.includes(clientIP)) {
    logger.warn(`Blocked request from blacklisted IP: ${clientIP}`);
    return res.status(403).send('Access Denied');
  }

  // Monitor suspicious behavior
  if (!suspiciousIPs.has(clientIP)) {
    suspiciousIPs.set(clientIP, { count: 0, timestamp: Date.now() });
  }

  const ipData = suspiciousIPs.get(clientIP);
  const now = Date.now();

  // Reset counter sau 1 phút
  if (now - ipData.timestamp > 60000) {
    ipData.count = 0;
    ipData.timestamp = now;
  }

  ipData.count++;

  // Nếu có quá nhiều requests trong 1 phút, thêm vào blacklist
  if (ipData.count > 200) {
    logger.error(`Adding ${clientIP} to blacklist due to suspicious activity`);
    blacklist.push(clientIP);
    return res.status(403).send('IP blocked due to suspicious activity');
  }

  next();
});

// Speed Limiter - làm chậm responses cho các clients gửi nhiều requests
const speedLimiter = slowDown({
  windowMs: 15 * 60 * 1000, // 15 phút
  delayAfter: 50, // Bắt đầu làm chậm sau 50 requests
  delayMs: (hits) => hits * 100, // Tăng delay 100ms cho mỗi request tiếp theo
});

// Rate Limiter - giới hạn số lượng requests
const rateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: 'Too many requests from this IP, please try again later.',
  handler: (req, res) => {
    logger.warn(`Rate limit exceeded for IP: ${req.ip}`);
    res.status(429).send('Too many requests, please try again later.');
  }
});

// Áp dụng các limiters
app.use(speedLimiter);
app.use(rateLimiter);

// Thiết lập timeout cho connections
app.use((req, res, next) => {
  res.setTimeout(5000, () => {
    res.status(408).send('Request timeout');
  });
  next();
});

// Route chính
app.get('/', (req, res) => {
  const clientIP = req.ip || req.connection.remoteAddress;
  logger.info(`Request received from IP: ${clientIP}`);
  res.json({
    message: 'Hello, this is a DDoS-protected server!',
    yourIP: clientIP
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  logger.error('Error:', err.stack);
  res.status(500).send('Something broke!');
});

// Khởi động server
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}`);
  logger.info(`Server started on port ${PORT}`);
});