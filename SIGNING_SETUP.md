# Android 签名配置说明

## 问题说明
为了解决 APK 安装时"签名不一致"的问题，需要使用固定的签名密钥进行构建。

## 生成签名密钥

### 1. 生成 Keystore 文件
在本地执行以下命令生成签名密钥：

```bash
keytool -genkey -v -keystore keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias yeah
```

按照提示填写信息，记住设置的密码。

### 2. 配置 key.properties
在 `android/` 目录下创建 `key.properties` 文件（从 `key.properties.example` 复制模板）：

```properties
storePassword=你的密钥库密码
keyPassword=你的密钥密码
keyAlias=yeah
storeFile=keystore.jks
```

将 `keystore.jks` 文件放在 `android/app/` 目录下。

## GitHub Actions CI 配置

### 1. 将 Keystore 转换为 Base64
```bash
base64 -i keystore.jks -o keystore.base64
```

### 2. 在 GitHub 仓库设置 Secrets
进入仓库 → Settings → Secrets and variables → Actions → New repository secret

添加以下 Secrets：

| Secret 名称 | 值 |
|------------|-----|
| `KEYSTORE_FILE` | `keystore.base64` 文件的内容 |
| `KEYSTORE_PASSWORD` | 密钥库密码（storePassword） |
| `KEY_PASSWORD` | 密钥密码（keyPassword） |
| `KEY_ALIAS` | 密钥别名（默认：yeah） |

### 3. 触发构建
推送代码后，GitHub Actions 会自动使用配置的签名密钥构建 APK。

## 本地构建测试

配置好 `key.properties` 和 `keystore.jks` 后，本地构建：

```bash
# Debug 版本
flutter build apk --debug

# Release 版本
flutter build apk --release
```

## 注意事项

⚠️ **重要**：
- 永远不要将 `key.properties` 和 `keystore.jks` 提交到 Git
- `.gitignore` 已配置忽略这些文件
- 妥善保管签名密钥文件和密码
- 如果丢失密钥，将无法更新已发布的应用

## 文件说明

- `android/key.properties.example` - 配置模板（已提交到 Git）
- `android/key.properties` - 实际配置（不要提交）
- `android/app/keystore.jks` - 签名密钥文件（不要提交）