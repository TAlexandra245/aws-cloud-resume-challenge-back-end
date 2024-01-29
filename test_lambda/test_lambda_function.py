import unittest
from unittest.mock import patch, MagicMock

from lambda_handler.lambda_function import lambda_handler


class Test(unittest.TestCase):
    @patch('lambda_handler.lambda_function.boto3.resource')
    def test_lambda_handler(self, mock_boto3_resource):

        # Mock DynamoDB resource
        mock_dynamodb_resource = MagicMock()
        mock_boto3_resource.return_value = mock_dynamodb_resource

        # Mock DynamoDB table
        mock_table = MagicMock()
        mock_dynamodb_resource.Table.return_value = mock_table

        # Mock DynamoDB get_item response
        mock_table.get_item.return_value = {
            "Item": {"value_id": 1, "counter_value": 0}
        }

        # Call the Lambda handler
        result = lambda_handler(None, None, dynamodb_resource=mock_dynamodb_resource)

        # Assertions
        self.assertEqual(result, 1)
        mock_table.get_item.assert_called_once_with(Key={"value_id": 1})
        mock_table.put_item.assert_called_once_with(Item={'value_id': 1, 'counter_value': 1})


if __name__ == '__main__':
    unittest.main()
