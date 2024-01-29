import os
import boto3


def lambda_handler(event: any, context: any, dynamodb_resource=None):
    dynamodb = dynamodb_resource or boto3.resource('dynamodb')
    table_name = os.environ['TABLE_NAME']
    table = dynamodb.Table(table_name)

    try:
        # Get the current visit count
        response = table.get_item(Key={"value_id": 1})

        if "Item" in response and "counter_value" in response["Item"]:
            visit_count = response['Item']['counter_value']
        else:
            raise Exception("Item with value not found")

        visit_count += 1

        # Update the counter value
        table.put_item(Item={
            'value_id': 1,
            'counter_value': visit_count
        })

        return visit_count

    except Exception as e:
        print(f"Error: {e}")
        return None

