// Vercel Serverless Function entry point for the backend API
require('dotenv').config();
const app = require('../backend/src/app');

module.exports = app;
