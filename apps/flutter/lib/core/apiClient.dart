import "dart:convert";
import "dart:typed_data";

import "package:dio/dio.dart";

import "config.dart";

/// 服务端统一响应结构 `{ code, data, message }` 解析失败时抛出的业务异常。
class ApiException implements Exception {
  final int code;
  final String message;

  const ApiException(this.code, this.message);

  @override
  String toString() => message;
}

/// 复用服务端 HTTP API 的客户端封装。
///
/// 所有业务接口均返回 `{ code, data, message }`，成功时 `code` 为 200，
/// 本类统一解包 `data` 并抛出 [ApiException] 描述失败原因。
class ApiClient {
  ApiClient({required String baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 60),
          ),
        );

  final Dio _dio;

  /// 会话 cookie 值（服务端登录后下发的 `gateway_session`）。
  String? sessionCookie;

  /// 已配对设备的 token（配对成功后设置，随所有请求头发送）。
  String? deviceToken;

  /// 会话失效回调（服务端返回 HTTP 401 时触发），用于跳回登录页。
  void Function()? onSessionExpired;

  void setSession(String? cookie) {
    sessionCookie = cookie;
  }

  void setDeviceToken(String? token) {
    deviceToken = token;
  }

  Map<String, String> get _headers {
    final headers = <String, String>{};
    if (sessionCookie != null && sessionCookie!.isNotEmpty) {
      headers["Cookie"] = "gateway_session=$sessionCookie";
    }
    if (deviceToken != null && deviceToken!.isNotEmpty) {
      headers[ServerFields.deviceTokenHeader] = deviceToken!;
      headers[ServerFields.appVersionHeader] = AppConfig.appVersion;
    }
    return headers;
  }

  Future<dynamic> getData(String path, {Map<String, dynamic>? query}) {
    return _request(
      () => _dio.get(path, queryParameters: query, options: Options(headers: _headers)),
    );
  }

  Future<dynamic> postData(String path, {Object? body}) {
    return _request(
      () => _dio.post(path, data: body, options: Options(headers: _headers)),
    );
  }

  /// 通用请求：支持任意方法、额外 header 与原始 body。
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Map<String, String>? headers,
    String? contentType,
  }) {
    return _request(
      () => _dio.request(
        path,
        queryParameters: query,
        data: body,
        options: Options(
          method: method,
          headers: {..._headers, ...?headers},
          contentType: contentType,
        ),
      ),
    );
  }

  /// 读取二进制内容（如图片素材），返回字节。
  Future<Uint8List> getBytes(String path, {Map<String, dynamic>? query}) async {
    final res = await _dio.get(
      path,
      queryParameters: query,
      options: Options(headers: _headers, responseType: ResponseType.bytes),
    );
    return res.data as Uint8List;
  }

  /// 流式请求：按行读取 NDJSON 响应，逐行产出原始 JSON 字符串（不含换行）。
  ///
  /// 供 Agent 对话等流式接口消费；空行（心跳）由调用方跳过。请求阶段失败会
  /// 抛出 [ApiException]，读取阶段的错误则作为流错误事件抛出。
  Stream<String> requestStream(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    Map<String, String>? headers,
    String? contentType,
  }) async* {
    Response<ResponseBody> res;
    try {
      res = await _dio.request<ResponseBody>(
        path,
        queryParameters: query,
        data: body,
        options: Options(
          method: method,
          responseType: ResponseType.stream,
          headers: {..._headers, ...?headers},
          contentType: contentType,
        ),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        onSessionExpired?.call();
      }
      final data = e.response?.data;
      if (data is Map<String, dynamic> && data["message"] != null) {
        throw ApiException(
          data["code"] is int ? data["code"] as int : -1,
          data["message"].toString(),
        );
      }
      throw ApiException(-1, e.message ?? "网络请求失败");
    }
    final responseBody = res.data;
    if (responseBody == null) return;
    var buffer = "";
    await for (final chunk in utf8.decoder.bind(responseBody.stream)) {
      buffer += chunk;
      while (true) {
        final index = buffer.indexOf("\n");
        if (index < 0) break;
        yield buffer.substring(0, index);
        buffer = buffer.substring(index + 1);
      }
    }
    if (buffer.isNotEmpty) yield buffer;
  }

  Future<dynamic> _request(Future<Response> Function() run) async {
    try {
      final res = await run();
      return _unwrap(res);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        onSessionExpired?.call();
      }
      final data = e.response?.data;
      if (data is Map<String, dynamic> && data["message"] != null) {
        throw ApiException(
          data["code"] is int ? data["code"] as int : -1,
          data["message"].toString(),
        );
      }
      throw ApiException(-1, e.message ?? "网络请求失败");
    }
  }

  dynamic _unwrap(Response res) {
    final data = res.data;
    if (data is Map<String, dynamic>) {
      final code = data["code"];
      if (code is int && code != 200) {
        throw ApiException(code, data["message"]?.toString() ?? "请求失败");
      }
      return data["data"];
    }
    // 非 JSON 响应（如文件二进制）原样返回。
    return data;
  }
}
