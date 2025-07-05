#!/bin/bash

# CloudFormation デプロイスクリプト
# 使用方法: ./deploy.sh <stack-name> <key-name> <allowed-cidr>

set -e

# パラメータチェック
if [ $# -ne 3 ]; then
    echo "使用方法: $0 <stack-name> <key-name> <allowed-cidr>"
    echo "例: $0 private-ec2-stack my-key-pair 203.0.113.0/24"
    exit 1
fi

STACK_NAME=$1
KEY_NAME=$2
ALLOWED_CIDR=$3
REGION="ap-northeast-1"
TEMPLATE_FILE="src/private-ec2-ssh.yaml"

echo "=== CloudFormation デプロイ開始 ==="
echo "スタック名: $STACK_NAME"
echo "キーペア名: $KEY_NAME"
echo "許可CIDR: $ALLOWED_CIDR"
echo "リージョン: $REGION"
echo ""

# キーペアの存在確認
echo "キーペアの存在確認中..."
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" > /dev/null 2>&1; then
    echo "エラー: キーペア '$KEY_NAME' が見つかりません"
    echo "既存のキーペア一覧:"
    aws ec2 describe-key-pairs --region "$REGION" --query 'KeyPairs[*].KeyName' --output table
    exit 1
fi
echo "✓ キーペア '$KEY_NAME' が見つかりました"

# スタックの存在確認
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" > /dev/null 2>&1; then
    echo "スタック '$STACK_NAME' は既に存在します。更新しますか？ (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "スタックを更新中..."
        aws cloudformation update-stack \
            --stack-name "$STACK_NAME" \
            --template-body "file://$TEMPLATE_FILE" \
            --parameters ParameterKey=KeyName,ParameterValue="$KEY_NAME" \
                         ParameterKey=AllowedSSHCidr,ParameterValue="$ALLOWED_CIDR" \
            --region "$REGION"
        
        echo "スタック更新完了を待機中..."
        aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$REGION"
    else
        echo "デプロイをキャンセルしました"
        exit 0
    fi
else
    echo "新しいスタックを作成中..."
    aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --template-body "file://$TEMPLATE_FILE" \
        --parameters ParameterKey=KeyName,ParameterValue="$KEY_NAME" \
                     ParameterKey=AllowedSSHCidr,ParameterValue="$ALLOWED_CIDR" \
        --region "$REGION"
    
    echo "スタック作成完了を待機中..."
    aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$REGION"
fi

echo ""
echo "=== デプロイ完了 ==="
echo "スタック出力値:"
aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs' \
    --output table

echo ""
echo "SSH接続例:"
echo "Bastionホスト: ssh -i /path/to/your-key.pem ec2-user@<BastionPublicIP>"
echo "Privateインスタンス: ssh -i /path/to/your-key.pem ec2-user@<PrivateIP> -J ec2-user@<BastionPublicIP>" 