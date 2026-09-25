import express from 'express';
import { router } from './routes/taskRoutes';

export const app = express();
app.use(express.json());
app.use('/', router);