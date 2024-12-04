# lambda/user-activity/index.py
import json

def handler(event, context):
    """
    Track user activities
    """
    try:
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'User activity logged successfully',
                'event': event
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }