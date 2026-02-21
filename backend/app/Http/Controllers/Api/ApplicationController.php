<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Application;
use App\Models\Shift;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ApplicationController extends Controller
{
    public function apply(Request $request, Shift $shift): JsonResponse
    {
        $user = $request->user();

        if ($user->role !== 'worker') {
            return response()->json(['message' => 'Откликаться могут только работники'], 403);
        }

        if ($shift->employer_id === $user->id) {
            return response()->json(['message' => 'Нельзя откликаться на свою смену'], 422);
        }

        $application = Application::firstOrCreate(
            [
                'shift_id' => $shift->id,
                'worker_id' => $user->id,
            ],
            [
                'status' => 'pending',
                'message' => $request->input('message'),
            ]
        );

        return response()->json(['data' => $application], 201);
    }

    public function myApplications(Request $request): JsonResponse
    {
        $user = $request->user();

        if ($user->role !== 'worker') {
            return response()->json(['message' => 'Только для работников'], 403);
        }

        $applications = Application::with('shift.employer:id,name')
            ->where('worker_id', $user->id)
            ->orderByDesc('created_at')
            ->get();

        return response()->json(['data' => $applications]);
    }

    public function updateStatus(Request $request, Application $application): JsonResponse
    {
        $user = $request->user();

        if ($user->role !== 'employer') {
            return response()->json(['message' => 'Только работодатель может менять статус'], 403);
        }

        $application->load('shift');
        if ($application->shift->employer_id !== $user->id) {
            return response()->json(['message' => 'Нет доступа к этому отклику'], 403);
        }

        $validated = $request->validate([
            'status' => ['required', 'in:pending,accepted,rejected'],
        ]);

        $application->update(['status' => $validated['status']]);

        return response()->json(['data' => $application]);
    }
}
