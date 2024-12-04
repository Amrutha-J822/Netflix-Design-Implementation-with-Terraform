# lambda/content-processor/index.py
import json

def handler(event, context):
    """
    Process content-related operations
    """
    try:
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Content processed successfully',
                'event': event
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }