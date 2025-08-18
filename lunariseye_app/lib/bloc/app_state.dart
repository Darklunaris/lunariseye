class AppStatus {
  final bool loading;
  AppStatus({this.loading = false});

  AppStatus copyWith({bool? loading}) =>
      AppStatus(loading: loading ?? this.loading);
}
