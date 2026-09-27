import boto3
import json
import os

ecs = boto3.client('ecs')

CLUSTER = os.environ['CLUSTER_NAME']
SERVICE = os.environ['SERVICE_NAME']
FAMILY = os.environ['TASK_FAMILY']

STEPS = sorted([(256, 512), (512, 1024), (1024, 2048), (2048, 4096)])


def handler(event, context):
    message = json.loads(event['Records'][0]['Sns']['Message'])
    alarm_name = message['AlarmName']
    new_state = message['NewStateValue']

    print(f"Alarm '{alarm_name}' entered state {new_state}")

    if new_state != 'ALARM':
        print("Not in ALARM state — ignoring (likely an OK/INSUFFICIENT_DATA transition).")
        return

    if 'high' in alarm_name:
        direction = 'up'
    elif 'low' in alarm_name:
        direction = 'down'
    else:
        print(f"Cannot infer scale direction from alarm name '{alarm_name}' — skipping.")
        return

    svc = ecs.describe_services(cluster=CLUSTER, services=[SERVICE])['services'][0]
    current_task_def_arn = svc['taskDefinition']
    task_def = ecs.describe_task_definition(taskDefinition=current_task_def_arn)['taskDefinition']

    current_cpu = int(task_def['cpu'])
    current_mem = int(task_def['memory'])

    idx = next((i for i, (c, m) in enumerate(STEPS) if c == current_cpu and m == current_mem), None)
    if idx is None:
        idx = min(range(len(STEPS)), key=lambda i: abs(STEPS[i][0] - current_cpu))
        print(f"Current ({current_cpu}, {current_mem}) not an exact step; snapping to nearest index {idx}.")

    new_idx = min(idx + 1, len(STEPS) - 1) if direction == 'up' else max(idx - 1, 0)
    new_cpu, new_mem = STEPS[new_idx]

    if (new_cpu, new_mem) == (current_cpu, current_mem):
        print(f"Already at the {'max' if direction == 'up' else 'min'} step ({current_cpu}, {current_mem}) — no change.")
        return

    print(f"Scaling {direction}: {current_cpu}/{current_mem} -> {new_cpu}/{new_mem}")

    container_defs = task_def['containerDefinitions']
    for c in container_defs:
        c['cpu'] = new_cpu
        c['memory'] = new_mem

    register_kwargs = {
        'family': FAMILY,
        'networkMode': task_def.get('networkMode'),
        'containerDefinitions': container_defs,
        'requiresCompatibilities': task_def.get('requiresCompatibilities'),
        'cpu': str(new_cpu),
        'memory': str(new_mem),
        'executionRoleArn': task_def.get('executionRoleArn'),
        'taskRoleArn': task_def.get('taskRoleArn'),
    }
    register_kwargs = {k: v for k, v in register_kwargs.items() if v is not None}

    new_task_def = ecs.register_task_definition(**register_kwargs)
    new_arn = new_task_def['taskDefinition']['taskDefinitionArn']

    ecs.update_service(
        cluster=CLUSTER,
        service=SERVICE,
        taskDefinition=new_arn,
        forceNewDeployment=True,
    )

    print(f"Deployed new task definition: {new_arn}")