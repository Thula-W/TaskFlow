import { Router } from 'express';
import {
  getHealth,
  createTask,
  listTasks,
  getTaskById,
  updateTask,
  deleteTask,
} from '../controllers/taskController.js';

export const router = Router();

router.get('/health', getHealth);
router.post('/tasks', createTask);
router.get('/tasks', listTasks);
router.get('/tasks/:id', getTaskById);
router.put('/tasks/:id', updateTask);
router.delete('/tasks/:id', deleteTask);