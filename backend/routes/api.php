<?php

use App\Http\Controllers\Api\ApplicationController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\ReviewController;
use App\Http\Controllers\Api\ShiftController;
use Illuminate\Support\Facades\Route;

Route::post('/register', [AuthController::class, 'register']);
Route::post('/login', [AuthController::class, 'login']);

Route::get('/shifts', [ShiftController::class, 'index']);
Route::get('/shifts/{shift}', [ShiftController::class, 'show']);

Route::middleware('auth:sanctum')->group(function () {
    Route::get('/me', [AuthController::class, 'me']);
    Route::post('/logout', [AuthController::class, 'logout']);

    Route::post('/shifts', [ShiftController::class, 'store']);
    Route::get('/my/shifts', [ShiftController::class, 'myShifts']);

    Route::post('/shifts/{shift}/apply', [ApplicationController::class, 'apply']);
    Route::patch('/applications/{application}/status', [ApplicationController::class, 'updateStatus']);
    Route::get('/my/applications', [ApplicationController::class, 'myApplications']);

    Route::post('/reviews', [ReviewController::class, 'store']);
});
