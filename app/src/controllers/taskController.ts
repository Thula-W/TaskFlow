import { Request, Response } from 'express';
import { pool } from '../db/index.js';
import { CreateTaskSchema, UpdateTaskSchema } from '../types/task.js';
import { logger } from '../utils/logger.js';

export const getHealth = async (_req: Request, res: Response): Promise<void> => {
  try {
    await pool.query('SELECT 1');
    res.status(200).json({ status: 'healthy', timestamp: new Date().toISOString() });
  } catch (error: any) {
    logger.error('Health check failed: DB unreachable', { error: error.message });
    res.status(503).json({ status: 'unhealthy', error: 'Database unavailable' });
  }
};

export const createTask = async (req: Request, res: Response): Promise<void> => {
  const validation = CreateTaskSchema.safeParse(req.body);
  if (!validation.success) {
    res.status(400).json({ error: 'Validation failed', details: validation.error.issues });
    return;
  }

  const { title, description, status } = validation.data;
  try {
    const result = await pool.query(
      `INSERT INTO tasks (title, description, status) 
       VALUES ($1, $2, $3) RETURNING *`,
      [title, description || null, status]
    );
    res.status(201).json(result.rows[0]);
  } catch (error: any) {
    logger.error('Error creating task', { error: error.message });
    res.status(500).json({ error: 'Internal server error' });
  }
};

export const listTasks = async (_req: Request, res: Response): Promise<void> => {
  try {
    const result = await pool.query('SELECT * FROM tasks ORDER BY created_at DESC');
    res.status(200).json(result.rows);
  } catch (error: any) {
    logger.error('Error listing tasks', { error: error.message });
    res.status(500).json({ error: 'Internal server error' });
  }
};

export const getTaskById = async (req: Request, res: Response): Promise<void> => {
  const { id } = req.params;
  try {
    const result = await pool.query('SELECT * FROM tasks WHERE id = $1', [id]);
    if (result.rows.length === 0) {
      res.status(404).json({ error: 'Task not found' });
      return;
    }
    res.status(200).json(result.rows[0]);
  } catch (error: any) {
    logger.error('Error fetching task', { id, error: error.message });
    res.status(500).json({ error: 'Internal server error' });
  }
};

export const updateTask = async (req: Request, res: Response): Promise<void> => {
  const { id } = req.params;
  const validation = UpdateTaskSchema.safeParse(req.body);
  if (!validation.success) {
    res.status(400).json({ error: 'Validation failed', details: validation.error.issues });
    return;
  }

  const fields = validation.data;
  const updates: string[] = [];
  const values: any[] = [];
  let idx = 1;

  if (fields.title) {
    updates.push(`title = $${idx++}`);
    values.push(fields.title);
  }
  if (fields.description !== undefined) {
    updates.push(`description = $${idx++}`);
    values.push(fields.description);
  }
  if (fields.status) {
    updates.push(`status = $${idx++}`);
    values.push(fields.status);
  }

  updates.push(`updated_at = CURRENT_TIMESTAMP`);
  values.push(id);

  try {
    const result = await pool.query(
      `UPDATE tasks SET ${updates.join(', ')} WHERE id = $${idx} RETURNING *`,
      values
    );
    if (result.rows.length === 0) {
      res.status(404).json({ error: 'Task not found' });
      return;
    }
    res.status(200).json(result.rows[0]);
  } catch (error: any) {
    logger.error('Error updating task', { id, error: error.message });
    res.status(500).json({ error: 'Internal server error' });
  }
};

export const deleteTask = async (req: Request, res: Response): Promise<void> => {
  const { id } = req.params;
  try {
    const result = await pool.query('DELETE FROM tasks WHERE id = $1 RETURNING id', [id]);
    if (result.rows.length === 0) {
      res.status(404).json({ error: 'Task not found' });
      return;
    }
    res.status(204).send();
  } catch (error: any) {
    logger.error('Error deleting task', { id, error: error.message });
    res.status(500).json({ error: 'Internal server error' });
  }
};