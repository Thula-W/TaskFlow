import { z } from 'zod';

export const CreateTaskSchema = z.object({
  title: z.string().min(1, 'Title cannot be empty').max(255),
  description: z.string().optional(),
  status: z.enum(['PENDING', 'IN_PROGRESS', 'COMPLETED']).optional().default('PENDING'),
});

export const UpdateTaskSchema = z.object({
  title: z.string().min(1).max(255).optional(),
  description: z.string().optional(),
  status: z.enum(['PENDING', 'IN_PROGRESS', 'COMPLETED']).optional(),
}).refine(data => Object.keys(data).length > 0, {
  message: 'At least one field must be provided to update',
});