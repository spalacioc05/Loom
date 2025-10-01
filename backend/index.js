
import express from "express";
import sql from './db/client.js';
import cors from 'cors';
import morgan from 'morgan';

const app = express();
const PORT = process.env.PORT || 3000;

import authRoute from './routes/routes.js';

// Middlewares
app.use(cors());
app.use(morgan('dev'));
app.use(express.json());

app.use('/', authRoute);

app.listen(PORT, async () => {
  console.log(`Server is running on port ${PORT}`);
  try {
    const result = await sql`SELECT NOW()`;
    console.log('Connected! Current time:', result[0].now);
  } catch (err) {
    console.error('Error testing PostgreSQL connection:', err);
  }
});