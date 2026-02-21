<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Review;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ReviewController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'to_user_id' => ['required', 'exists:users,id'],
            'rating' => ['required', 'integer', 'between:1,5'],
            'comment' => ['nullable', 'string', 'max:1000'],
        ]);

        if ((int) $validated['to_user_id'] === (int) $request->user()->id) {
            return response()->json(['message' => 'Нельзя оставлять отзыв себе'], 422);
        }

        $review = Review::create([
            ...$validated,
            'from_user_id' => $request->user()->id,
        ]);

        $target = User::findOrFail($validated['to_user_id']);

        return response()->json([
            'data' => $review,
            'target_rating' => round((float) $target->reviewsAboutMe()->avg('rating'), 1),
            'target_reviews_count' => $target->reviewsAboutMe()->count(),
        ], 201);
    }
}
