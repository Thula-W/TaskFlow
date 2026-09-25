import request from 'supertest';
import { app } from '../src/app';
import { pool } from '../src/db';

jest.mock('../src/db', () => ({
  pool: {
    query: jest.fn(),
  },
}));

describe('TaskFlow API Endpoints', () => {
  afterEach(() => {
    jest.clearAllMocks();
  });

  describe('GET /health', () => {
    it('returns 200 when database responds', async () => {
      (pool.query as jest.Mock).mockResolvedValueOnce({ rows: [{ '?column?': 1 }] });
      const res = await request(app).get('/health');
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('healthy');
    });

    it('returns 503 when database fails', async () => {
      (pool.query as jest.Mock).mockRejectedValueOnce(new Error('Connection failed'));
      const res = await request(app).get('/health');
      expect(res.status).toBe(503);
      expect(res.body.status).toBe('unhealthy');
    });
  });

  describe('POST /tasks', () => {
    it('creates a task with valid inputs', async () => {
      const mockTask = { id: 'uuid-1', title: 'Test Task', status: 'PENDING' };
      (pool.query as jest.Mock).mockResolvedValueOnce({ rows: [mockTask] });

      const res = await request(app).post('/tasks').send({ title: 'Test Task' });
      expect(res.status).toBe(201);
      expect(res.body).toEqual(mockTask);
    });

    it('returns 400 when title is missing', async () => {
      const res = await request(app).post('/tasks').send({});
      expect(res.status).toBe(400);
      expect(res.body.error).toBe('Validation failed');
    });
  });

  describe('GET /tasks', () => {
    it('returns a list of tasks', async () => {
      const mockTasks = [{ id: 'uuid-1', title: 'Task 1' }];
      (pool.query as jest.Mock).mockResolvedValueOnce({ rows: mockTasks });

      const res = await request(app).get('/tasks');
      expect(res.status).toBe(200);
      expect(res.body).toEqual(mockTasks);
    });
  });

  describe('GET /tasks/:id', () => {
    it('returns task when found', async () => {
      const mockTask = { id: 'uuid-1', title: 'Task 1' };
      (pool.query as jest.Mock).mockResolvedValueOnce({ rows: [mockTask] });

      const res = await request(app).get('/tasks/uuid-1');
      expect(res.status).toBe(200);
      expect(res.body).toEqual(mockTask);
    });

    it('returns 404 when task not found', async () => {
      (pool.query as jest.Mock).mockResolvedValueOnce({ rows: [] });

      const res = await request(app).get('/tasks/missing-id');
      expect(res.status).toBe(404);
    });
  });

  describe('PUT /tasks/:id', () => {
    it('updates a task successfully', async () => {
      const updatedTask = { id: 'uuid-1', title: 'New Title' };
      (pool.query as jest.Mock).mockResolvedValueOnce({ rows: [updatedTask] });

      const res = await request(app).put('/tasks/uuid-1').send({ title: 'New Title' });
      expect(res.status).toBe(200);
      expect(res.body).toEqual(updatedTask);
    });

    it('returns 400 if body is empty', async () => {
      const res = await request(app).put('/tasks/uuid-1').send({});
      expect(res.status).toBe(400);
    });
  });

  describe('DELETE /tasks/:id', () => {
    it('deletes a task successfully', async () => {
      (pool.query as jest.Mock).mockResolvedValueOnce({ rows: [{ id: 'uuid-1' }] });
      const res = await request(app).delete('/tasks/uuid-1');
      expect(res.status).toBe(204);
    });

    it('returns 404 if task to delete does not exist', async () => {
      (pool.query as jest.Mock).mockResolvedValueOnce({ rows: [] });
      const res = await request(app).delete('/tasks/uuid-1');
      expect(res.status).toBe(404);
    });
  });
});