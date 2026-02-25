<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

Route::view('/legal/privacy', 'legal.privacy')->name('legal.privacy');
Route::view('/legal/terms', 'legal.terms')->name('legal.terms');
Route::view('/legal/support', 'legal.support')->name('legal.support');
