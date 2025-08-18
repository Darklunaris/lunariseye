import 'package:bloc/bloc.dart';
import 'app_event.dart';
import 'app_state.dart';

class AppBloc extends Bloc<AppEvent, AppStatus> {
  AppBloc() : super(AppStatus()) {
    on<LoadAppEvent>((event, emit) async {
      emit(state.copyWith(loading: true));
      await Future.delayed(const Duration(milliseconds: 200));
      emit(state.copyWith(loading: false));
    });
  }
}
